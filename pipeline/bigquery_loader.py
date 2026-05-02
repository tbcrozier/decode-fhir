"""
BigQuery Loader

Handles loading parsed FHIR records into BigQuery tables with run tracking
for data lineage and reproducibility.
"""

import json
from datetime import datetime, timezone

from google.cloud import bigquery
from google.cloud.exceptions import NotFound


class BigQueryLoader:
    """Loads parsed FHIR data into BigQuery with run tracking."""

    def __init__(self, project_id: str, dataset_id: str = "fhir_analytics"):
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.client = bigquery.Client(project=project_id)
        self.full_dataset_id = f"{project_id}.{dataset_id}"

    def start_run(
        self,
        run_id: str,
        source_bucket: str,
        source_prefix: str,
        parameters: dict
    ) -> None:
        """Record the start of a pipeline run."""
        table_id = f"{self.full_dataset_id}.pipeline_runs"

        run_record = {
            "run_id": run_id,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "status": "running",
            "source_bucket": source_bucket,
            "source_prefix": source_prefix,
            "parameters": json.dumps(parameters)
        }

        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        )

        job = self.client.load_table_from_json(
            [run_record],
            table_id,
            job_config=job_config
        )
        job.result()

    def complete_run(
        self,
        run_id: str,
        files_processed: int,
        patients_loaded: int,
        conditions_loaded: int,
        observations_loaded: int,
        status: str = "success",
        error_message: str | None = None
    ) -> None:
        """Update the pipeline run record with completion details."""
        table_id = f"{self.full_dataset_id}.pipeline_runs"

        query = f"""
        UPDATE `{table_id}`
        SET
            completed_at = CURRENT_TIMESTAMP(),
            status = @status,
            files_processed = @files_processed,
            patients_loaded = @patients_loaded,
            conditions_loaded = @conditions_loaded,
            observations_loaded = @observations_loaded,
            error_message = @error_message
        WHERE run_id = @run_id
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("run_id", "STRING", run_id),
                bigquery.ScalarQueryParameter("status", "STRING", status),
                bigquery.ScalarQueryParameter("files_processed", "INT64", files_processed),
                bigquery.ScalarQueryParameter("patients_loaded", "INT64", patients_loaded),
                bigquery.ScalarQueryParameter("conditions_loaded", "INT64", conditions_loaded),
                bigquery.ScalarQueryParameter("observations_loaded", "INT64", observations_loaded),
                bigquery.ScalarQueryParameter("error_message", "STRING", error_message),
            ]
        )

        job = self.client.query(query, job_config=job_config)
        job.result()

    def add_run_metadata(
        self,
        records: dict[str, list[dict]],
        run_id: str
    ) -> dict[str, list[dict]]:
        """Add run_id and loaded_at to all records."""
        loaded_at = datetime.now(timezone.utc).isoformat()

        for record_type in records:
            for record in records[record_type]:
                record["run_id"] = run_id
                record["loaded_at"] = loaded_at

        return records

    def load_records(
        self,
        records: dict[str, list[dict]],
        write_disposition: str = "WRITE_APPEND"
    ) -> dict[str, int]:
        """
        Load parsed records into BigQuery tables.

        Args:
            records: Dict with keys 'patients', 'conditions', 'observations'
                     Records should already have run_id and loaded_at added
            write_disposition: WRITE_APPEND, WRITE_TRUNCATE, or WRITE_EMPTY

        Returns:
            Dict with row counts loaded per table
        """
        results = {}

        table_mapping = {
            "patients": "patients",
            "conditions": "conditions",
            "observations": "observations"
        }

        for record_type, table_name in table_mapping.items():
            data = records.get(record_type, [])
            if not data:
                results[table_name] = 0
                continue

            table_id = f"{self.full_dataset_id}.{table_name}"

            job_config = bigquery.LoadJobConfig(
                write_disposition=write_disposition,
                source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            )

            job = self.client.load_table_from_json(
                data,
                table_id,
                job_config=job_config
            )
            job.result()  # Wait for completion

            results[table_name] = len(data)

        return results

    def get_table_counts(self) -> dict[str, int]:
        """Get current row counts for all tables."""
        counts = {}
        tables = ["patients", "conditions", "observations"]

        for table in tables:
            table_id = f"{self.full_dataset_id}.{table}"
            try:
                table_ref = self.client.get_table(table_id)
                counts[table] = table_ref.num_rows
            except NotFound:
                counts[table] = 0

        return counts

    def get_run_history(self, limit: int = 10) -> list[dict]:
        """Get recent pipeline runs."""
        query = f"""
        SELECT
            run_id,
            started_at,
            completed_at,
            status,
            files_processed,
            patients_loaded,
            conditions_loaded,
            observations_loaded,
            TIMESTAMP_DIFF(completed_at, started_at, SECOND) as duration_seconds
        FROM `{self.full_dataset_id}.pipeline_runs`
        ORDER BY started_at DESC
        LIMIT {limit}
        """

        result = self.client.query(query).result()
        return [dict(row) for row in result]

    def delete_run(self, run_id: str) -> dict[str, int]:
        """Delete all data associated with a specific run (rollback)."""
        deleted = {}

        for table in ["patients", "conditions", "observations"]:
            query = f"""
            DELETE FROM `{self.full_dataset_id}.{table}`
            WHERE run_id = @run_id
            """
            job_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("run_id", "STRING", run_id),
                ]
            )
            job = self.client.query(query, job_config=job_config)
            job.result()
            deleted[table] = job.num_dml_affected_rows

        return deleted

    def write_qc_summary(self, run_id: str, metrics: dict) -> None:
        """
        Write QC summary metrics for a pipeline run.

        Args:
            run_id: Pipeline run identifier
            metrics: Dict containing:
                - files_processed: Number of files successfully processed
                - files_failed: Number of files that failed processing
                - patients_count: Number of patient records loaded
                - conditions_count: Number of condition records loaded
                - observations_count: Number of observation records loaded
                - processing_duration_seconds: Total processing time
                - records_per_second: Processing throughput
                - observation_date_min: Earliest observation date
                - observation_date_max: Latest observation date
        """
        table_id = f"{self.full_dataset_id}.qc_summary"

        # Calculate derived metrics
        files_processed = metrics.get("files_processed", 0)
        files_failed = metrics.get("files_failed", 0)
        total_files = files_processed + files_failed
        success_rate = (files_processed / total_files * 100) if total_files > 0 else 0

        patients_count = metrics.get("patients_count", 0)
        conditions_count = metrics.get("conditions_count", 0)
        observations_count = metrics.get("observations_count", 0)

        conditions_per_patient = (
            conditions_count / patients_count if patients_count > 0 else 0
        )
        observations_per_patient = (
            observations_count / patients_count if patients_count > 0 else 0
        )

        qc_record = {
            "run_id": run_id,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "files_processed": files_processed,
            "files_failed": files_failed,
            "success_rate": success_rate,
            "patients_count": patients_count,
            "conditions_count": conditions_count,
            "observations_count": observations_count,
            "conditions_per_patient": conditions_per_patient,
            "observations_per_patient": observations_per_patient,
            "observation_date_min": metrics.get("observation_date_min"),
            "observation_date_max": metrics.get("observation_date_max"),
            "processing_duration_seconds": metrics.get("processing_duration_seconds", 0),
            "records_per_second": metrics.get("records_per_second", 0),
        }

        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        )

        job = self.client.load_table_from_json(
            [qc_record],
            table_id,
            job_config=job_config
        )
        job.result()
