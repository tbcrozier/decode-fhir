"""
FHIR Bundle Parser

Extracts and flattens Patient, Condition, and Observation resources
from Synthea-generated FHIR R4 bundles.
"""

import json
from datetime import datetime
from typing import Any


def parse_bundle(bundle_json: dict) -> dict[str, list[dict]]:
    """
    Parse a FHIR Bundle and extract resources into flattened records.

    Args:
        bundle_json: Parsed FHIR Bundle JSON

    Returns:
        Dict with keys 'patients', 'conditions', 'observations' containing
        flattened records ready for BigQuery.
    """
    records = {
        "patients": [],
        "conditions": [],
        "observations": []
    }

    load_timestamp = datetime.utcnow().isoformat()

    entries = bundle_json.get("entry", [])

    for entry in entries:
        resource = entry.get("resource", {})
        resource_type = resource.get("resourceType")

        if resource_type == "Patient":
            records["patients"].append(parse_patient(resource, load_timestamp))
        elif resource_type == "Condition":
            records["conditions"].append(parse_condition(resource, load_timestamp))
        elif resource_type == "Observation":
            records["observations"].append(parse_observation(resource, load_timestamp))

    return records


def parse_patient(resource: dict, load_timestamp: str) -> dict:
    """Extract patient demographics from FHIR Patient resource."""

    # Extract US Core race extension
    race = None
    ethnicity = None
    for ext in resource.get("extension", []):
        url = ext.get("url", "")
        if "us-core-race" in url:
            race = _get_extension_text(ext)
        elif "us-core-ethnicity" in url:
            ethnicity = _get_extension_text(ext)

    # Extract address
    address = {}
    addresses = resource.get("address", [])
    if addresses:
        addr = addresses[0]
        address = {
            "city": addr.get("city"),
            "state": addr.get("state"),
            "postal_code": addr.get("postalCode")
        }

    # Handle deceased - can be boolean or dateTime
    deceased = None
    deceased_date = None
    if "deceasedDateTime" in resource:
        deceased = True
        deceased_date = _parse_date(resource["deceasedDateTime"])
    elif "deceasedBoolean" in resource:
        deceased = resource["deceasedBoolean"]

    return {
        "patient_id": resource.get("id"),
        "birth_date": _parse_date(resource.get("birthDate")),
        "gender": resource.get("gender"),
        "race": race,
        "ethnicity": ethnicity,
        "city": address.get("city"),
        "state": address.get("state"),
        "postal_code": address.get("postal_code"),
        "deceased": deceased,
        "deceased_date": deceased_date,
        "loaded_at": load_timestamp
    }


def parse_condition(resource: dict, load_timestamp: str) -> dict:
    """Extract condition data from FHIR Condition resource."""

    # Get coding from code.coding array
    code = None
    code_display = None
    codings = resource.get("code", {}).get("coding", [])
    if codings:
        code = codings[0].get("code")
        code_display = codings[0].get("display")

    # Clinical status
    clinical_status = None
    status_codings = resource.get("clinicalStatus", {}).get("coding", [])
    if status_codings:
        clinical_status = status_codings[0].get("code")

    # Extract patient reference (format: "Patient/uuid")
    patient_id = _extract_reference_id(resource.get("subject", {}).get("reference"))

    return {
        "condition_id": resource.get("id"),
        "patient_id": patient_id,
        "code": code,
        "code_display": code_display,
        "clinical_status": clinical_status,
        "onset_date": _parse_date(resource.get("onsetDateTime")),
        "abatement_date": _parse_date(resource.get("abatementDateTime")),
        "loaded_at": load_timestamp
    }


def parse_observation(resource: dict, load_timestamp: str) -> dict:
    """Extract observation data from FHIR Observation resource."""

    # Get coding
    code = None
    code_display = None
    codings = resource.get("code", {}).get("coding", [])
    if codings:
        code = codings[0].get("code")
        code_display = codings[0].get("display")

    # Get category
    category = None
    categories = resource.get("category", [])
    if categories:
        cat_codings = categories[0].get("coding", [])
        if cat_codings:
            category = cat_codings[0].get("code")

    # Get value - can be valueQuantity, valueString, valueCodeableConcept, etc.
    value_quantity = None
    value_unit = None
    value_string = None

    if "valueQuantity" in resource:
        vq = resource["valueQuantity"]
        value_quantity = vq.get("value")
        value_unit = vq.get("unit")
    elif "valueString" in resource:
        value_string = resource["valueString"]
    elif "valueCodeableConcept" in resource:
        codings = resource["valueCodeableConcept"].get("coding", [])
        if codings:
            value_string = codings[0].get("display")

    # Extract patient reference
    patient_id = _extract_reference_id(resource.get("subject", {}).get("reference"))

    return {
        "observation_id": resource.get("id"),
        "patient_id": patient_id,
        "code": code,
        "code_display": code_display,
        "category": category,
        "value_quantity": value_quantity,
        "value_unit": value_unit,
        "value_string": value_string,
        "effective_date": resource.get("effectiveDateTime"),
        "loaded_at": load_timestamp
    }


def _get_extension_text(extension: dict) -> str | None:
    """Extract text value from US Core extension."""
    for ext in extension.get("extension", []):
        if ext.get("url") == "text":
            return ext.get("valueString")
    return None


def _extract_reference_id(reference: str | None) -> str | None:
    """Extract ID from FHIR reference string (e.g., 'Patient/uuid' -> 'uuid')."""
    if reference and "/" in reference:
        return reference.split("/")[-1]
    return reference


def _parse_date(date_str: str | None) -> str | None:
    """Parse date/datetime string, returning just the date portion."""
    if not date_str:
        return None
    # Handle both date and datetime formats
    return date_str[:10] if len(date_str) >= 10 else date_str
