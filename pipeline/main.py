"""
FHIR Data Pipeline

Ingests Synthea FHIR bundles from GCS, parses clinical resources,
and loads them into BigQuery for analytics.

Usage:
    python main.py --project-id YOUR_PROJECT --source-bucket synthea-fhir-decode
"""

import argparse
import json
import logging
import uuid
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed
from google.cloud import storage

from fhir_parser import parse_bundle
from bigquery_loader import BigQueryLoader

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def list_fhir_bundles(bucket_name: str, prefix: str = "raw/synthea_tennessee_500/") -> list[str]:
    """List all JSON files in the source bucket."""
    client = storage.Client()
    bucket = client.bucket(bucket_name)

    blobs = bucket.list_blobs(prefix=prefix)
    json_files = [blob.name for blob in blobs if blob.name.endswith(".json")]

    logger.info(f"Found {len(json_files)} FHIR bundles in gs://{bucket_name}/{prefix}")
    return json_files


def download_and_parse(bucket_name: str, blob_name: str) -> dict[str, list[dict]]:
    """Download a FHIR bundle from GCS and parse it."""
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_name)

    content = blob.download_as_text()
    bundle = json.loads(content)

    return parse_bundle(bundle)


def merge_records(all_records: list[dict]) -> dict[str, list[dict]]:
    """Merge parsed records from multiple bundles."""
    merged = {
        "patients": [],
        "conditions": [],
        "observations": []
    }

    for records in all_records:
        for key in merged:
            merged[key].extend(records.get(key, []))

    return merged


def run_pipeline(
    project_id: str,
    source_bucket: str,
    source_prefix: str = "raw/synthea_tennessee_500/",
    max_files: int | None = None,
    batch_size: int = 100,
    max_workers: int = 10
):
    """
    Run the full FHIR ingestion pipeline.

    Args:
        project_id: GCP project ID
        source_bucket: GCS bucket containing FHIR bundles
        source_prefix: Prefix path within bucket
        max_files: Limit number of files to process (for testing)
        batch_size: Number of files to process before loading to BQ
        max_workers: Number of parallel download threads
    """
    # Generate unique run ID: YYYYMMDD_HHMMSS_shortUUID
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    run_id = f"{timestamp}_{uuid.uuid4().hex[:8]}"

    logger.info(f"Starting FHIR data pipeline - Run ID: {run_id}")
    logger.info(f"Source: gs://{source_bucket}/{source_prefix}")
    logger.info(f"Destination: {project_id}.fhir_analytics")

    # Initialize BigQuery loader
    loader = BigQueryLoader(project_id)

    # Track run parameters for reproducibility
    parameters = {
        "source_bucket": source_bucket,
        "source_prefix": source_prefix,
        "max_files": max_files,
        "batch_size": batch_size,
        "max_workers": max_workers
    }

    # Register run start
    loader.start_run(run_id, source_bucket, source_prefix, parameters)

    try:
        # List all bundles
        bundle_files = list_fhir_bundles(source_bucket, source_prefix)

        if max_files:
            bundle_files = bundle_files[:max_files]
            logger.info(f"Limited to {max_files} files for processing")

        # Process in batches
        total_loaded = {"patients": 0, "conditions": 0, "observations": 0}
        files_processed = 0

        for batch_start in range(0, len(bundle_files), batch_size):
            batch_files_subset = bundle_files[batch_start:batch_start + batch_size]
            batch_num = (batch_start // batch_size) + 1
            total_batches = (len(bundle_files) + batch_size - 1) // batch_size

            logger.info(f"Processing batch {batch_num}/{total_batches} ({len(batch_files_subset)} files)")

            # Download and parse in parallel
            all_records = []
            with ThreadPoolExecutor(max_workers=max_workers) as executor:
                futures = {
                    executor.submit(download_and_parse, source_bucket, blob_name): blob_name
                    for blob_name in batch_files_subset
                }

                for future in as_completed(futures):
                    blob_name = futures[future]
                    try:
                        records = future.result()
                        all_records.append(records)
                        files_processed += 1
                    except Exception as e:
                        logger.error(f"Failed to process {blob_name}: {e}")

            # Merge and add run metadata
            merged = merge_records(all_records)
            merged = loader.add_run_metadata(merged, run_id)

            logger.info(
                f"Batch contains: {len(merged['patients'])} patients, "
                f"{len(merged['conditions'])} conditions, "
                f"{len(merged['observations'])} observations"
            )

            results = loader.load_records(merged)

            for table, count in results.items():
                total_loaded[table] += count

        # Mark run as successful
        loader.complete_run(
            run_id=run_id,
            files_processed=files_processed,
            patients_loaded=total_loaded["patients"],
            conditions_loaded=total_loaded["conditions"],
            observations_loaded=total_loaded["observations"],
            status="success"
        )

        # Final summary
        logger.info("Pipeline completed successfully")
        logger.info(f"Run ID: {run_id}")
        logger.info(f"Total loaded: {total_loaded}")

        # Show final table counts
        final_counts = loader.get_table_counts()
        logger.info(f"Final table row counts: {final_counts}")

    except Exception as e:
        # Mark run as failed
        loader.complete_run(
            run_id=run_id,
            files_processed=0,
            patients_loaded=0,
            conditions_loaded=0,
            observations_loaded=0,
            status="failed",
            error_message=str(e)
        )
        logger.error(f"Pipeline failed: {e}")
        raise


def main():
    parser = argparse.ArgumentParser(
        description="FHIR Data Pipeline - Ingest Synthea bundles into BigQuery"
    )
    parser.add_argument(
        "--project-id",
        required=True,
        help="GCP project ID"
    )
    parser.add_argument(
        "--source-bucket",
        default="synthea-fhir-decode",
        help="Source GCS bucket containing FHIR bundles"
    )
    parser.add_argument(
        "--source-prefix",
        default="raw/synthea_tennessee_500/",
        help="Prefix path within source bucket"
    )
    parser.add_argument(
        "--max-files",
        type=int,
        default=None,
        help="Limit number of files to process (for testing)"
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=100,
        help="Number of files to process per batch"
    )

    args = parser.parse_args()

    run_pipeline(
        project_id=args.project_id,
        source_bucket=args.source_bucket,
        source_prefix=args.source_prefix,
        max_files=args.max_files,
        batch_size=args.batch_size
    )


if __name__ == "__main__":
    main()
