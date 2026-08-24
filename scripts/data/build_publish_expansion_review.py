#!/usr/bin/env python3
"""Build the local human-review table for public store expansion."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
import uuid
from collections import Counter
from pathlib import Path
from typing import Any, Mapping, Sequence
from urllib.parse import urlparse


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from store_publishing_common import (  # noqa: E402
    StorePublishingError,
    normalize_store_text,
    parse_coordinate,
    read_csv_rows,
    write_csv_rows,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_STAGING_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_stores_staging.csv"
)
DEFAULT_PUBLISH_REVIEW_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_store_publish_review.csv"
)
DEFAULT_STYLE_REVIEW_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_style_review.csv"
)
DEFAULT_HOLD_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_staging_hold_report.csv"
)
DEFAULT_EVIDENCE_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_burger_publish_expansion_evidence.json"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_burger_publish_expansion_review.csv"
)

OUTPUT_HEADERS = (
    "reviewNumber",
    "storeId",
    "candidateId",
    "name",
    "address",
    "latitude",
    "longitude",
    "currentPublishDecision",
    "currentIsActive",
    "currentBurgerStyle",
    "operatingStatusAssessment",
    "nameAssessment",
    "addressAssessment",
    "coordinateAssessment",
    "burgerSpecialtyAssessment",
    "officialSourceAvailable",
    "evidenceCount",
    "recentEvidenceCount",
    "source1Type",
    "source1Title",
    "source1Url",
    "source1PublishedAt",
    "source2Type",
    "source2Title",
    "source2Url",
    "source2PublishedAt",
    "latestEvidenceAsOf",
    "conflictStatus",
    "recommendedDecision",
    "recommendationReason",
    "reviewerNote",
)

STAGING_REQUIRED_HEADERS = {
    "candidateId",
    "displayName",
    "address",
    "latitude",
    "longitude",
}
PUBLISH_REQUIRED_HEADERS = {
    "storeId",
    "candidateId",
    "name",
    "address",
    "latitude",
    "longitude",
    "publishDecision",
    "isActive",
}
STYLE_REQUIRED_HEADERS = {
    "storeId",
    "candidateId",
    "name",
    "address",
    "proposedBurgerStyle",
    "reviewStatus",
}
HOLD_REQUIRED_HEADERS = {"candidateId", "name", "stagingStatus"}

ALLOWED_SOURCE_TYPES = {
    "official",
    "public_platform",
    "news",
    "government",
    "independent",
    "other",
}
ALLOWED_OPERATING_ASSESSMENTS = {
    "currently_operating",
    "unclear",
    "possible_closed",
}
ALLOWED_NAME_ASSESSMENTS = {"match", "variant", "conflict"}
ALLOWED_ADDRESS_ASSESSMENTS = {"match", "variant", "conflict"}
ALLOWED_COORDINATE_ASSESSMENTS = {
    "no_known_conflict",
    "limited_evidence",
    "conflict",
}
ALLOWED_SPECIALTY_ASSESSMENTS = {"confirmed", "unclear", "not_specialty"}
ALLOWED_CONFLICT_STATUSES = {"none", "minor", "material"}
ALLOWED_RECOMMENDATIONS = {
    "ready_for_user_approval",
    "needs_manual_check",
    "likely_closed_needs_user_decision",
}
OFFICIAL_SOURCE_TYPE = "official"
MAX_RECOMMENDED_STORES = 9
RECENT_EVIDENCE_DAYS = 180
SECRET_PATTERN = re.compile(
    r"(?:AIza[0-9A-Za-z_-]{30,}|sb_(?:publishable|secret)_[0-9A-Za-z_-]{20,}|"
    r"eyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+)"
)


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _index_unique(
    rows: Sequence[Mapping[str, str]],
    field: str,
    label: str,
) -> dict[str, Mapping[str, str]]:
    indexed: dict[str, Mapping[str, str]] = {}
    for row in rows:
        value = row.get(field, "").strip()
        if not value or value in indexed:
            raise StorePublishingError(f"{label} has an empty or duplicate {field}: {value}")
        indexed[value] = row
    return indexed


def _parse_bool(value: str, field: str, row_id: str) -> bool:
    normalized = value.strip().lower()
    if normalized not in {"true", "false"}:
        raise StorePublishingError(f"{field} must be true or false: {row_id}")
    return normalized == "true"


def _require_choice(
    value: Any,
    allowed: set[str],
    field: str,
    candidate_id: str,
) -> str:
    normalized = str(value or "").strip()
    if normalized not in allowed:
        raise StorePublishingError(
            f"Unsupported {field} for {candidate_id}: {normalized}"
        )
    return normalized


def _parse_evidence_date(value: Any, candidate_id: str) -> dt.date | None:
    normalized = str(value or "").strip()
    if normalized in {"", "unknown"}:
        return None
    try:
        return dt.date.fromisoformat(normalized)
    except ValueError:
        raise StorePublishingError(
            f"Evidence date must be YYYY-MM-DD or unknown: {candidate_id}"
        ) from None


def _validate_source(
    source: Mapping[str, Any],
    candidate_id: str,
    checked_at: dt.date,
) -> dict[str, Any]:
    source_type = _require_choice(
        source.get("type"), ALLOWED_SOURCE_TYPES, "source type", candidate_id
    )
    title = str(source.get("title") or "").strip()
    url = str(source.get("url") or "").strip()
    published_at_value = str(source.get("publishedAt") or "unknown").strip()
    published_at = _parse_evidence_date(published_at_value, candidate_id)
    supports = str(source.get("supports") or "").strip()
    checked_directly = source.get("checkedDirectly") is True
    current_page_state = source.get("currentPageState") is True
    if not title or not supports or not checked_directly:
        raise StorePublishingError(
            f"Evidence title, support note, and direct check are required: {candidate_id}"
        )
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https" or not parsed_url.netloc:
        raise StorePublishingError(f"Evidence URL must use HTTPS: {candidate_id}")
    if SECRET_PATTERN.search(url):
        raise StorePublishingError(f"Evidence URL contains a secret-like value: {candidate_id}")
    if published_at is not None and published_at > checked_at:
        raise StorePublishingError(f"Evidence date is in the future: {candidate_id}")

    is_recent = False
    if published_at is not None:
        is_recent = (checked_at - published_at).days <= RECENT_EVIDENCE_DAYS
    elif current_page_state and source_type in {"official", "public_platform"}:
        is_recent = True

    return {
        "type": source_type,
        "title": title,
        "url": url,
        "publishedAt": published_at_value or "unknown",
        "supports": supports,
        "checkedDirectly": True,
        "currentPageState": current_page_state,
        "isRecent": is_recent,
    }


def _validate_evidence_store(
    raw: Mapping[str, Any],
    checked_at: dt.date,
    style_row: Mapping[str, str],
) -> dict[str, Any]:
    candidate_id = str(raw.get("candidateId") or "").strip()
    if not candidate_id:
        raise StorePublishingError("Evidence candidateId is required.")
    operating = _require_choice(
        raw.get("operatingStatusAssessment"),
        ALLOWED_OPERATING_ASSESSMENTS,
        "operatingStatusAssessment",
        candidate_id,
    )
    name_assessment = _require_choice(
        raw.get("nameAssessment"),
        ALLOWED_NAME_ASSESSMENTS,
        "nameAssessment",
        candidate_id,
    )
    address_assessment = _require_choice(
        raw.get("addressAssessment"),
        ALLOWED_ADDRESS_ASSESSMENTS,
        "addressAssessment",
        candidate_id,
    )
    coordinate_assessment = _require_choice(
        raw.get("coordinateAssessment"),
        ALLOWED_COORDINATE_ASSESSMENTS,
        "coordinateAssessment",
        candidate_id,
    )
    specialty_assessment = _require_choice(
        raw.get("burgerSpecialtyAssessment"),
        ALLOWED_SPECIALTY_ASSESSMENTS,
        "burgerSpecialtyAssessment",
        candidate_id,
    )
    conflict_status = _require_choice(
        raw.get("conflictStatus"),
        ALLOWED_CONFLICT_STATUSES,
        "conflictStatus",
        candidate_id,
    )
    recommendation = _require_choice(
        raw.get("recommendedDecision"),
        ALLOWED_RECOMMENDATIONS,
        "recommendedDecision",
        candidate_id,
    )
    reason = str(raw.get("recommendationReason") or "").strip()
    if not reason:
        raise StorePublishingError(f"Recommendation reason is required: {candidate_id}")

    sources_value = raw.get("sources")
    if not isinstance(sources_value, list) or not 1 <= len(sources_value) <= 2:
        raise StorePublishingError(f"One or two evidence sources are required: {candidate_id}")
    sources = [
        _validate_source(source, candidate_id, checked_at)
        for source in sources_value
        if isinstance(source, Mapping)
    ]
    if len(sources) != len(sources_value):
        raise StorePublishingError(f"Evidence sources must be objects: {candidate_id}")
    if len({source["url"] for source in sources}) != len(sources):
        raise StorePublishingError(f"Evidence source URLs must be unique: {candidate_id}")

    official_available = any(
        source["type"] == OFFICIAL_SOURCE_TYPE for source in sources
    )
    recent_count = sum(1 for source in sources if source["isRecent"])
    latest_dates = [
        parsed
        for source in sources
        if (parsed := _parse_evidence_date(source["publishedAt"], candidate_id))
        is not None
    ]
    latest_as_of = str(raw.get("latestEvidenceAsOf") or "").strip()
    if latest_as_of:
        latest_date = _parse_evidence_date(latest_as_of, candidate_id)
        if latest_date is None or latest_date > checked_at:
            raise StorePublishingError(f"Invalid latestEvidenceAsOf: {candidate_id}")
    elif latest_dates:
        latest_as_of = max(latest_dates).isoformat()
    else:
        latest_as_of = checked_at.isoformat()

    if recommendation == "ready_for_user_approval":
        blockers = (
            operating != "currently_operating",
            name_assessment == "conflict",
            address_assessment == "conflict",
            coordinate_assessment == "conflict",
            specialty_assessment != "confirmed",
            conflict_status == "material",
            style_row.get("reviewStatus", "").strip() == "needs_recheck",
            not official_available and recent_count < 2,
        )
        if any(blockers):
            raise StorePublishingError(
                f"Approval recommendation does not meet the evidence gate: {candidate_id}"
            )
    if recommendation == "likely_closed_needs_user_decision" and operating != "possible_closed":
        raise StorePublishingError(
            f"Likely-closed recommendation requires possible_closed: {candidate_id}"
        )

    return {
        "candidateId": candidate_id,
        "operatingStatusAssessment": operating,
        "nameAssessment": name_assessment,
        "addressAssessment": address_assessment,
        "coordinateAssessment": coordinate_assessment,
        "burgerSpecialtyAssessment": specialty_assessment,
        "officialSourceAvailable": official_available,
        "sources": sources,
        "latestEvidenceAsOf": latest_as_of,
        "conflictStatus": conflict_status,
        "recommendedDecision": recommendation,
        "recommendationReason": reason,
        "reviewerNote": str(raw.get("reviewerNote") or "").strip(),
    }


def _load_evidence(
    path: Path,
    style_by_candidate: Mapping[str, Mapping[str, str]],
) -> tuple[dt.date, dict[str, dict[str, Any]]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise StorePublishingError(f"Unable to read evidence JSON: {path}") from error
    if not isinstance(payload, Mapping):
        raise StorePublishingError("Evidence JSON root must be an object.")
    try:
        checked_at = dt.date.fromisoformat(str(payload.get("checkedAt") or ""))
    except ValueError:
        raise StorePublishingError("Evidence checkedAt must be YYYY-MM-DD.") from None
    raw_stores = payload.get("stores")
    if not isinstance(raw_stores, list):
        raise StorePublishingError("Evidence stores must be a list.")
    indexed: dict[str, dict[str, Any]] = {}
    for raw in raw_stores:
        if not isinstance(raw, Mapping):
            raise StorePublishingError("Every evidence store must be an object.")
        candidate_id = str(raw.get("candidateId") or "").strip()
        if candidate_id not in style_by_candidate:
            raise StorePublishingError(f"Unknown evidence candidateId: {candidate_id}")
        if candidate_id in indexed:
            raise StorePublishingError(f"Duplicate evidence candidateId: {candidate_id}")
        indexed[candidate_id] = _validate_evidence_store(
            raw,
            checked_at,
            style_by_candidate[candidate_id],
        )
    return checked_at, indexed


def _validate_joined_inputs(
    staging_rows: Sequence[Mapping[str, str]],
    publish_rows: Sequence[Mapping[str, str]],
    style_rows: Sequence[Mapping[str, str]],
    hold_rows: Sequence[Mapping[str, str]],
) -> tuple[
    dict[str, Mapping[str, str]],
    dict[str, Mapping[str, str]],
    set[str],
]:
    staging_by_candidate = _index_unique(staging_rows, "candidateId", "staging")
    publish_by_candidate = _index_unique(publish_rows, "candidateId", "publish review")
    style_by_candidate = _index_unique(style_rows, "candidateId", "style review")
    hold_by_candidate = _index_unique(hold_rows, "candidateId", "hold report")
    candidate_sets = (
        set(staging_by_candidate),
        set(publish_by_candidate),
        set(style_by_candidate),
    )
    if len({frozenset(values) for values in candidate_sets}) != 1:
        raise StorePublishingError("Staging, publish review, and style review stores differ.")
    if set(staging_by_candidate) & set(hold_by_candidate):
        raise StorePublishingError("A hold store is present in the publishing inputs.")

    seen_store_ids: set[str] = set()
    for candidate_id, publish_row in publish_by_candidate.items():
        staging_row = staging_by_candidate[candidate_id]
        style_row = style_by_candidate[candidate_id]
        try:
            store_id = str(uuid.UUID(publish_row.get("storeId", "").strip()))
            style_store_id = str(uuid.UUID(style_row.get("storeId", "").strip()))
        except ValueError:
            raise StorePublishingError(f"Invalid storeId UUID: {candidate_id}") from None
        if store_id in seen_store_ids or store_id != style_store_id:
            raise StorePublishingError(f"Duplicate or mismatched storeId: {candidate_id}")
        seen_store_ids.add(store_id)
        identity_mismatches = []
        for field, staging_field in (
            ("name", "displayName"),
            ("address", "address"),
        ):
            expected = normalize_store_text(publish_row.get(field, ""))
            if expected != normalize_store_text(staging_row.get(staging_field, "")):
                identity_mismatches.append(field)
            if expected != normalize_store_text(style_row.get(field, "")):
                identity_mismatches.append(f"style_{field}")
        latitude = parse_coordinate(
            publish_row.get("latitude", ""), "latitude", candidate_id
        )
        longitude = parse_coordinate(
            publish_row.get("longitude", ""), "longitude", candidate_id
        )
        staging_latitude = parse_coordinate(
            staging_row.get("latitude", ""), "latitude", candidate_id
        )
        staging_longitude = parse_coordinate(
            staging_row.get("longitude", ""), "longitude", candidate_id
        )
        if latitude != staging_latitude or longitude != staging_longitude:
            identity_mismatches.append("coordinates")
        if identity_mismatches:
            raise StorePublishingError(
                f"Input identity mismatch for {candidate_id}: {identity_mismatches}"
            )
    return publish_by_candidate, style_by_candidate, set(hold_by_candidate)


def _preserved_reviewer_notes(
    output_path: Path,
    expected_candidate_ids: set[str],
) -> dict[str, str]:
    if not output_path.exists():
        return {}
    headers, rows = read_csv_rows(output_path, set(OUTPUT_HEADERS))
    if headers != list(OUTPUT_HEADERS):
        raise StorePublishingError("Existing expansion review headers changed.")
    existing = _index_unique(rows, "candidateId", "existing expansion review")
    if set(existing) != expected_candidate_ids:
        raise StorePublishingError("Existing expansion review store set changed.")
    return {
        candidate_id: row.get("reviewerNote", "")
        for candidate_id, row in existing.items()
    }


def build_publish_expansion_review(
    staging_path: Path,
    publish_review_path: Path,
    style_review_path: Path,
    hold_path: Path,
    evidence_path: Path,
    output_path: Path,
    expected_pending_rows: int | None = None,
) -> list[dict[str, str]]:
    input_paths = (
        staging_path,
        publish_review_path,
        style_review_path,
        hold_path,
    )
    input_hashes = {path: file_sha256(path) for path in input_paths}
    _, staging_rows = read_csv_rows(staging_path, STAGING_REQUIRED_HEADERS)
    _, publish_rows = read_csv_rows(publish_review_path, PUBLISH_REQUIRED_HEADERS)
    _, style_rows = read_csv_rows(style_review_path, STYLE_REQUIRED_HEADERS)
    _, hold_rows = read_csv_rows(hold_path, HOLD_REQUIRED_HEADERS)
    _, style_by_candidate, hold_ids = _validate_joined_inputs(
        staging_rows,
        publish_rows,
        style_rows,
        hold_rows,
    )

    pending_rows: list[Mapping[str, str]] = []
    for row in publish_rows:
        candidate_id = row.get("candidateId", "").strip()
        decision = row.get("publishDecision", "").strip()
        is_active = _parse_bool(row.get("isActive", ""), "isActive", candidate_id)
        if decision == "pending" and not is_active:
            pending_rows.append(row)
        elif decision == "verified" and is_active:
            continue
        else:
            raise StorePublishingError(
                f"Unexpected publishing state in expansion input: {candidate_id}"
            )
    if expected_pending_rows is not None and len(pending_rows) != expected_pending_rows:
        raise StorePublishingError(
            f"Expected {expected_pending_rows} pending stores, found {len(pending_rows)}."
        )

    pending_ids = {row.get("candidateId", "").strip() for row in pending_rows}
    if pending_ids & hold_ids:
        raise StorePublishingError("A hold store is present in the pending review set.")
    _, evidence_by_candidate = _load_evidence(evidence_path, style_by_candidate)
    if set(evidence_by_candidate) != pending_ids:
        missing = sorted(pending_ids - set(evidence_by_candidate))
        extra = sorted(set(evidence_by_candidate) - pending_ids)
        raise StorePublishingError(
            f"Evidence store set differs from pending stores. missing={missing}, extra={extra}"
        )
    ready_count = sum(
        evidence["recommendedDecision"] == "ready_for_user_approval"
        for evidence in evidence_by_candidate.values()
    )
    if ready_count > MAX_RECOMMENDED_STORES:
        raise StorePublishingError(
            f"At most {MAX_RECOMMENDED_STORES} stores may be recommended."
        )

    preserved_notes = _preserved_reviewer_notes(output_path, pending_ids)
    output_rows: list[dict[str, str]] = []
    for review_number, publish_row in enumerate(pending_rows, start=1):
        candidate_id = publish_row.get("candidateId", "").strip()
        evidence = evidence_by_candidate[candidate_id]
        style_row = style_by_candidate[candidate_id]
        sources = evidence["sources"]
        source1 = sources[0]
        source2 = sources[1] if len(sources) > 1 else None
        style = style_row.get("proposedBurgerStyle", "").strip()
        if style_row.get("reviewStatus", "").strip() != "approved":
            style = "unclassified"
        output_rows.append(
            {
                "reviewNumber": str(review_number),
                "storeId": publish_row.get("storeId", "").strip(),
                "candidateId": candidate_id,
                "name": publish_row.get("name", "").strip(),
                "address": publish_row.get("address", "").strip(),
                "latitude": publish_row.get("latitude", "").strip(),
                "longitude": publish_row.get("longitude", "").strip(),
                "currentPublishDecision": publish_row.get(
                    "publishDecision", ""
                ).strip(),
                "currentIsActive": publish_row.get("isActive", "").strip().lower(),
                "currentBurgerStyle": style or "unclassified",
                "operatingStatusAssessment": evidence[
                    "operatingStatusAssessment"
                ],
                "nameAssessment": evidence["nameAssessment"],
                "addressAssessment": evidence["addressAssessment"],
                "coordinateAssessment": evidence["coordinateAssessment"],
                "burgerSpecialtyAssessment": evidence[
                    "burgerSpecialtyAssessment"
                ],
                "officialSourceAvailable": str(
                    evidence["officialSourceAvailable"]
                ).lower(),
                "evidenceCount": str(len(sources)),
                "recentEvidenceCount": str(
                    sum(1 for source in sources if source["isRecent"])
                ),
                "source1Type": source1["type"],
                "source1Title": source1["title"],
                "source1Url": source1["url"],
                "source1PublishedAt": source1["publishedAt"],
                "source2Type": source2["type"] if source2 else "",
                "source2Title": source2["title"] if source2 else "",
                "source2Url": source2["url"] if source2 else "",
                "source2PublishedAt": source2["publishedAt"] if source2 else "",
                "latestEvidenceAsOf": evidence["latestEvidenceAsOf"],
                "conflictStatus": evidence["conflictStatus"],
                "recommendedDecision": evidence["recommendedDecision"],
                "recommendationReason": evidence["recommendationReason"],
                "reviewerNote": preserved_notes.get(
                    candidate_id, evidence["reviewerNote"]
                ),
            }
        )

    if any(row["currentPublishDecision"] != "pending" for row in output_rows):
        raise StorePublishingError("Expansion review may contain pending stores only.")
    if any(row["currentIsActive"] != "false" for row in output_rows):
        raise StorePublishingError("Expansion review may not activate stores.")
    write_csv_rows(output_path, OUTPUT_HEADERS, output_rows)
    if input_hashes != {path: file_sha256(path) for path in input_paths}:
        raise StorePublishingError("An input CSV changed while building the review.")
    return output_rows


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staging", type=Path, default=DEFAULT_STAGING_PATH)
    parser.add_argument(
        "--publish-review", type=Path, default=DEFAULT_PUBLISH_REVIEW_PATH
    )
    parser.add_argument(
        "--style-review", type=Path, default=DEFAULT_STYLE_REVIEW_PATH
    )
    parser.add_argument("--hold-report", type=Path, default=DEFAULT_HOLD_PATH)
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--expected-pending", type=int, default=23)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows = build_publish_expansion_review(
            args.staging,
            args.publish_review,
            args.style_review,
            args.hold_report,
            args.evidence,
            args.output,
            args.expected_pending,
        )
    except StorePublishingError as error:
        print(f"Review generation stopped safely: {error}", file=sys.stderr)
        return 1
    decisions = Counter(row["recommendedDecision"] for row in rows)
    print(f"Created {args.output} with {len(rows)} pending stores.")
    print(
        "Recommendations: "
        + ", ".join(f"{key}={value}" for key, value in sorted(decisions.items()))
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
