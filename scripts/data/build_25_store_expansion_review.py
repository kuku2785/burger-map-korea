#!/usr/bin/env python3
"""Build the local Phase 6B review table for the 25-store milestone."""

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
DEFAULT_PUBLISH_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_store_publish_review.csv"
)
DEFAULT_STYLE_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_style_review.csv"
)
DEFAULT_STAGING_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_stores_staging.csv"
)
DEFAULT_HOLD_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_staging_hold_report.csv"
)
DEFAULT_KAKAO_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_discovery_reviewed.csv"
)
DEFAULT_CANDIDATE_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_candidates_reviewed.csv"
)
DEFAULT_EVIDENCE_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_burger_25_store_expansion_evidence.json"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_burger_25_store_expansion_review.csv"
)

OUTPUT_HEADERS = (
    "reviewItemId",
    "sourceGroup",
    "storeId",
    "candidateId",
    "discoveryId",
    "sourcePlaceId",
    "name",
    "address",
    "latitude",
    "longitude",
    "currentPublishDecision",
    "currentIsActive",
    "currentBurgerStyle",
    "originalHoldReason",
    "operatingStatusAssessment",
    "identityAssessment",
    "addressAssessment",
    "coordinateAssessment",
    "burgerSpecialtyAssessment",
    "styleAssessment",
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
    "remainingRisk",
    "reviewerNote",
)

PUBLISH_HEADERS = {
    "storeId",
    "candidateId",
    "name",
    "address",
    "latitude",
    "longitude",
    "publishDecision",
    "isActive",
}
STYLE_HEADERS = {
    "storeId",
    "candidateId",
    "name",
    "address",
    "proposedBurgerStyle",
    "reviewStatus",
}
STAGING_HEADERS = {
    "candidateId",
    "displayName",
    "address",
    "latitude",
    "longitude",
}
HOLD_HEADERS = {
    "candidateId",
    "sourcePlaceId",
    "name",
    "previousStatus",
    "stagingStatus",
    "holdReason",
}
KAKAO_HEADERS = {
    "discoveryId",
    "sourcePlaceId",
    "name",
    "address",
    "latitude",
    "longitude",
}
CANDIDATE_HEADERS = {
    "candidateId",
    "name",
    "address",
    "latitude",
    "longitude",
}

ALLOWED_SOURCE_TYPES = {
    "official",
    "public_platform",
    "government",
    "news",
    "independent",
    "other",
}
ALLOWED_OPERATING = {"currently_operating", "unclear", "possible_closed"}
ALLOWED_IDENTITY = {"match", "variant", "likely_moved", "conflict"}
ALLOWED_ADDRESS = {"match", "variant", "unresolved", "conflict"}
ALLOWED_COORDINATES = {"no_known_conflict", "limited_evidence", "conflict"}
ALLOWED_SPECIALTY = {"confirmed", "unclear", "not_specialty"}
ALLOWED_STYLE = {"confirmed", "unclassified_allowed", "needs_recheck"}
ALLOWED_CONFLICTS = {"none", "minor", "material"}
ALLOWED_RECOMMENDATIONS = {
    "ready_for_user_approval",
    "needs_manual_check",
    "hold_resolved_ready_for_user_approval",
    "hold_still_needs_manual_check",
    "likely_closed_needs_user_decision",
    "not_burger_specialist_needs_user_decision",
    "duplicate_or_replacement_needs_user_decision",
}
READY_RECOMMENDATIONS = {
    "ready_for_user_approval",
    "hold_resolved_ready_for_user_approval",
}
SECRET_PATTERN = re.compile(
    r"(?:AIza[0-9A-Za-z_-]{30,}|sb_(?:publishable|secret)_[0-9A-Za-z_-]{20,}|"
    r"eyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+|"
    r"https://[a-z0-9]{15,}\.supabase\.co)",
    re.IGNORECASE,
)
RECENT_DAYS = 180
EXPECTED_PENDING = 14
EXPECTED_HOLD = 4
EXPECTED_PUBLIC = 10
MAX_RECOMMENDATIONS = 15
TARGET_PUBLIC_STORES = 25


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _index_unique(
    rows: Sequence[Mapping[str, str]], field: str, label: str
) -> dict[str, Mapping[str, str]]:
    result: dict[str, Mapping[str, str]] = {}
    for row in rows:
        value = row.get(field, "").strip()
        if not value or value in result:
            raise StorePublishingError(f"{label} has an empty or duplicate {field}.")
        result[value] = row
    return result


def _parse_bool(value: str, field: str, row_id: str) -> bool:
    normalized = value.strip().lower()
    if normalized not in {"true", "false"}:
        raise StorePublishingError(f"{field} must be true or false: {row_id}")
    return normalized == "true"


def _require_choice(value: Any, allowed: set[str], field: str, item_id: str) -> str:
    normalized = str(value or "").strip()
    if normalized not in allowed:
        raise StorePublishingError(f"Unsupported {field} for {item_id}: {normalized}")
    return normalized


def _parse_date(value: Any, item_id: str) -> dt.date | None:
    normalized = str(value or "").strip()
    if normalized in {"", "unknown"}:
        return None
    try:
        return dt.date.fromisoformat(normalized)
    except ValueError:
        raise StorePublishingError(
            f"Evidence date must be YYYY-MM-DD or unknown: {item_id}"
        ) from None


def stable_review_item_id(identity: Mapping[str, str]) -> str:
    parts = (
        identity.get("sourceGroup", "").strip(),
        identity.get("storeId", "").strip(),
        identity.get("candidateId", "").strip(),
        identity.get("discoveryId", "").strip(),
        identity.get("sourcePlaceId", "").strip(),
    )
    if not parts[0] or not parts[2]:
        raise StorePublishingError("Stable review identity requires sourceGroup and candidateId.")
    digest = hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:24]
    return f"p6b_{digest}"


def _validate_source(
    source: Mapping[str, Any], item_id: str, checked_at: dt.date
) -> dict[str, Any]:
    source_type = _require_choice(
        source.get("type"), ALLOWED_SOURCE_TYPES, "source type", item_id
    )
    title = str(source.get("title") or "").strip()
    url = str(source.get("url") or "").strip()
    published_value = str(source.get("publishedAt") or "unknown").strip()
    published_at = _parse_date(published_value, item_id)
    checked_directly = source.get("checkedDirectly") is True
    current_signal = source.get("currentOperationalSignal") is True
    supports = str(source.get("supports") or "").strip()
    parsed = urlparse(url)
    if not title or not supports or not checked_directly:
        raise StorePublishingError(
            f"Evidence title, support note, and direct check are required: {item_id}"
        )
    if parsed.scheme != "https" or not parsed.netloc:
        raise StorePublishingError(f"Evidence URL must use HTTPS: {item_id}")
    if SECRET_PATTERN.search(url):
        raise StorePublishingError(f"Evidence URL contains a secret-like value: {item_id}")
    if published_at is not None and published_at > checked_at:
        raise StorePublishingError(f"Evidence date is in the future: {item_id}")
    recent = bool(
        (published_at is not None and (checked_at - published_at).days <= RECENT_DAYS)
        or current_signal
    )
    return {
        "type": source_type,
        "title": title,
        "url": url,
        "publishedAt": published_value,
        "supports": supports,
        "checkedDirectly": True,
        "currentOperationalSignal": current_signal,
        "isRecent": recent,
    }


def _validate_evidence_item(
    raw: Mapping[str, Any], expected: Mapping[str, str], checked_at: dt.date
) -> dict[str, Any]:
    item_id = stable_review_item_id(expected)
    for field in (
        "sourceGroup",
        "storeId",
        "candidateId",
        "discoveryId",
        "sourcePlaceId",
    ):
        if str(raw.get(field) or "").strip() != expected.get(field, "").strip():
            raise StorePublishingError(f"Evidence identity mismatch for {item_id}: {field}")
    for field in ("name", "address"):
        if normalize_store_text(str(raw.get(field) or "")) != normalize_store_text(
            expected.get(field, "")
        ):
            raise StorePublishingError(f"Evidence {field} mismatch for {item_id}.")

    operating = _require_choice(
        raw.get("operatingStatusAssessment"), ALLOWED_OPERATING, "operating status", item_id
    )
    identity = _require_choice(
        raw.get("identityAssessment"), ALLOWED_IDENTITY, "identity assessment", item_id
    )
    address = _require_choice(
        raw.get("addressAssessment"), ALLOWED_ADDRESS, "address assessment", item_id
    )
    coordinates = _require_choice(
        raw.get("coordinateAssessment"),
        ALLOWED_COORDINATES,
        "coordinate assessment",
        item_id,
    )
    specialty = _require_choice(
        raw.get("burgerSpecialtyAssessment"),
        ALLOWED_SPECIALTY,
        "burger specialty assessment",
        item_id,
    )
    style = _require_choice(
        raw.get("styleAssessment"), ALLOWED_STYLE, "style assessment", item_id
    )
    conflict = _require_choice(
        raw.get("conflictStatus"), ALLOWED_CONFLICTS, "conflict status", item_id
    )
    recommendation = _require_choice(
        raw.get("recommendedDecision"),
        ALLOWED_RECOMMENDATIONS,
        "recommended decision",
        item_id,
    )
    reason = str(raw.get("recommendationReason") or "").strip()
    risk = str(raw.get("remainingRisk") or "").strip()
    if not reason or not risk:
        raise StorePublishingError(f"Recommendation reason and risk are required: {item_id}")

    source_values = raw.get("sources")
    if not isinstance(source_values, list) or not 1 <= len(source_values) <= 2:
        raise StorePublishingError(f"One or two evidence sources are required: {item_id}")
    sources = [
        _validate_source(source, item_id, checked_at)
        for source in source_values
        if isinstance(source, Mapping)
    ]
    if len(sources) != len(source_values):
        raise StorePublishingError(f"Evidence sources must be objects: {item_id}")
    if len({source["url"] for source in sources}) != len(sources):
        raise StorePublishingError(f"Evidence source URLs must be unique: {item_id}")

    official = any(source["type"] == "official" for source in sources)
    recent_count = sum(1 for source in sources if source["isRecent"])
    latest_dates = [
        date
        for source in sources
        if (date := _parse_date(source["publishedAt"], item_id)) is not None
    ]
    latest = str(raw.get("latestEvidenceAsOf") or "").strip()
    if latest:
        latest_date = _parse_date(latest, item_id)
        if latest_date is None or latest_date > checked_at:
            raise StorePublishingError(f"Invalid latestEvidenceAsOf: {item_id}")
    elif latest_dates:
        latest = max(latest_dates).isoformat()
    else:
        latest = checked_at.isoformat()

    source_group = expected["sourceGroup"]
    if recommendation in READY_RECOMMENDATIONS:
        if source_group == "pending" and recommendation != "ready_for_user_approval":
            raise StorePublishingError(f"Pending store uses a hold recommendation: {item_id}")
        if source_group == "hold" and recommendation != "hold_resolved_ready_for_user_approval":
            raise StorePublishingError(f"Hold store uses a pending recommendation: {item_id}")
        blockers = (
            operating != "currently_operating",
            identity not in {"match", "variant"},
            address not in {"match", "variant"},
            coordinates == "conflict",
            specialty != "confirmed",
            conflict == "material",
            not official and recent_count < 2,
        )
        if any(blockers):
            raise StorePublishingError(f"Recommendation does not pass safety gate: {item_id}")
    if recommendation.startswith("hold_") and source_group != "hold":
        raise StorePublishingError(f"Hold recommendation used outside hold group: {item_id}")
    if recommendation == "likely_closed_needs_user_decision" and operating != "possible_closed":
        raise StorePublishingError(f"Likely-closed decision requires possible_closed: {item_id}")
    if (
        recommendation == "not_burger_specialist_needs_user_decision"
        and specialty != "not_specialty"
    ):
        raise StorePublishingError(f"Non-specialist decision requires not_specialty: {item_id}")

    return {
        "operatingStatusAssessment": operating,
        "identityAssessment": identity,
        "addressAssessment": address,
        "coordinateAssessment": coordinates,
        "burgerSpecialtyAssessment": specialty,
        "styleAssessment": style,
        "officialSourceAvailable": official,
        "sources": sources,
        "recentEvidenceCount": recent_count,
        "latestEvidenceAsOf": latest,
        "conflictStatus": conflict,
        "recommendedDecision": recommendation,
        "recommendationReason": reason,
        "remainingRisk": risk,
    }


def _load_evidence(
    path: Path, identities: Sequence[Mapping[str, str]]
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
    raw_items = payload.get("items")
    if not isinstance(raw_items, list):
        raise StorePublishingError("Evidence items must be a list.")
    expected_by_id = {stable_review_item_id(row): row for row in identities}
    if len(expected_by_id) != len(identities):
        raise StorePublishingError("Generated reviewItemId values are not unique.")
    result: dict[str, dict[str, Any]] = {}
    for raw in raw_items:
        if not isinstance(raw, Mapping):
            raise StorePublishingError("Every evidence item must be an object.")
        provisional = {
            field: str(raw.get(field) or "").strip()
            for field in (
                "sourceGroup",
                "storeId",
                "candidateId",
                "discoveryId",
                "sourcePlaceId",
            )
        }
        item_id = stable_review_item_id(provisional)
        if item_id not in expected_by_id or item_id in result:
            raise StorePublishingError(f"Unknown or duplicate evidence identity: {item_id}")
        result[item_id] = _validate_evidence_item(
            raw, expected_by_id[item_id], checked_at
        )
    if set(result) != set(expected_by_id):
        raise StorePublishingError("Evidence identity set differs from review targets.")
    return checked_at, result


def _build_identities(
    publish_rows: Sequence[Mapping[str, str]],
    style_rows: Sequence[Mapping[str, str]],
    staging_rows: Sequence[Mapping[str, str]],
    hold_rows: Sequence[Mapping[str, str]],
    kakao_rows: Sequence[Mapping[str, str]],
    candidate_rows: Sequence[Mapping[str, str]],
) -> tuple[list[dict[str, str]], int]:
    publish_by_candidate = _index_unique(publish_rows, "candidateId", "publish review")
    style_by_candidate = _index_unique(style_rows, "candidateId", "style review")
    staging_by_candidate = _index_unique(staging_rows, "candidateId", "staging")
    if set(publish_by_candidate) != set(style_by_candidate) or set(publish_by_candidate) != set(
        staging_by_candidate
    ):
        raise StorePublishingError("Publish, style, and staging store sets differ.")

    pending: list[Mapping[str, str]] = []
    public_count = 0
    seen_store_ids: set[str] = set()
    for row in publish_rows:
        candidate_id = row["candidateId"].strip()
        try:
            store_id = str(uuid.UUID(row["storeId"].strip()))
        except ValueError:
            raise StorePublishingError(f"Invalid storeId: {candidate_id}") from None
        if store_id in seen_store_ids:
            raise StorePublishingError(f"Duplicate storeId: {candidate_id}")
        seen_store_ids.add(store_id)
        decision = row["publishDecision"].strip()
        active = _parse_bool(row["isActive"], "isActive", candidate_id)
        if decision == "pending" and not active:
            pending.append(row)
        elif decision == "verified" and active:
            public_count += 1
        else:
            raise StorePublishingError(f"Unexpected publishing state: {candidate_id}")

        style = style_by_candidate[candidate_id]
        staging = staging_by_candidate[candidate_id]
        if style["storeId"].strip() != store_id:
            raise StorePublishingError(f"Style storeId mismatch: {candidate_id}")
        for left, right in (("name", "displayName"), ("address", "address")):
            if normalize_store_text(row[left]) != normalize_store_text(staging[right]):
                raise StorePublishingError(f"Staging identity mismatch: {candidate_id}")
            if normalize_store_text(row[left]) != normalize_store_text(style[left]):
                raise StorePublishingError(f"Style identity mismatch: {candidate_id}")
        if parse_coordinate(row["latitude"], "latitude", candidate_id) != parse_coordinate(
            staging["latitude"], "latitude", candidate_id
        ) or parse_coordinate(row["longitude"], "longitude", candidate_id) != parse_coordinate(
            staging["longitude"], "longitude", candidate_id
        ):
            raise StorePublishingError(f"Staging coordinates mismatch: {candidate_id}")

    if len(pending) != EXPECTED_PENDING or public_count != EXPECTED_PUBLIC:
        raise StorePublishingError(
            f"Expected {EXPECTED_PENDING} pending and {EXPECTED_PUBLIC} public stores; "
            f"found {len(pending)} and {public_count}."
        )
    if len(hold_rows) != EXPECTED_HOLD:
        raise StorePublishingError(f"Expected {EXPECTED_HOLD} hold stores.")

    identities: list[dict[str, str]] = []
    for row in pending:
        candidate_id = row["candidateId"].strip()
        style = style_by_candidate[candidate_id]
        identities.append(
            {
                "sourceGroup": "pending",
                "storeId": row["storeId"].strip(),
                "candidateId": candidate_id,
                "discoveryId": "",
                "sourcePlaceId": staging_by_candidate[candidate_id].get(
                    "sourcePlaceId", ""
                ).strip(),
                "name": row["name"].strip(),
                "address": row["address"].strip(),
                "latitude": row["latitude"].strip(),
                "longitude": row["longitude"].strip(),
                "currentPublishDecision": "pending",
                "currentIsActive": "false",
                "currentBurgerStyle": style["proposedBurgerStyle"].strip()
                or "unclassified",
                "originalHoldReason": "",
            }
        )

    kakao_by_place: dict[str, list[Mapping[str, str]]] = {}
    for row in kakao_rows:
        place_id = row.get("sourcePlaceId", "").strip()
        if place_id:
            kakao_by_place.setdefault(place_id, []).append(row)
    candidate_by_id = _index_unique(candidate_rows, "candidateId", "candidate review")
    pending_candidate_ids = {row["candidateId"] for row in identities}
    for hold in hold_rows:
        candidate_id = hold["candidateId"].strip()
        if candidate_id in pending_candidate_ids:
            raise StorePublishingError(f"Pending and hold overlap: {candidate_id}")
        place_id = hold.get("sourcePlaceId", "").strip()
        if place_id:
            matches = kakao_by_place.get(place_id, [])
            if len(matches) != 1:
                raise StorePublishingError(f"Hold place identity is ambiguous: {candidate_id}")
            source = matches[0]
            discovery_id = source["discoveryId"].strip()
        else:
            source = candidate_by_id.get(candidate_id)
            if source is None:
                raise StorePublishingError(f"Hold candidate identity is missing: {candidate_id}")
            discovery_id = ""
        if normalize_store_text(source["name"]) != normalize_store_text(hold["name"]):
            raise StorePublishingError(f"Hold name mismatch: {candidate_id}")
        parse_coordinate(source["latitude"], "latitude", candidate_id)
        parse_coordinate(source["longitude"], "longitude", candidate_id)
        identities.append(
            {
                "sourceGroup": "hold",
                "storeId": "",
                "candidateId": candidate_id,
                "discoveryId": discovery_id,
                "sourcePlaceId": place_id,
                "name": source["name"].strip(),
                "address": source["address"].strip(),
                "latitude": source["latitude"].strip(),
                "longitude": source["longitude"].strip(),
                "currentPublishDecision": hold["previousStatus"].strip(),
                "currentIsActive": "false",
                "currentBurgerStyle": "unclassified",
                "originalHoldReason": hold["holdReason"].strip(),
            }
        )

    if len(identities) != EXPECTED_PENDING + EXPECTED_HOLD:
        raise StorePublishingError("Unexpected total review target count.")
    candidate_ids = [row["candidateId"] for row in identities]
    if len(candidate_ids) != len(set(candidate_ids)):
        raise StorePublishingError("Review targets contain duplicate candidateId values.")
    return identities, public_count


def _preserved_notes(
    output_path: Path, expected_ids: set[str]
) -> dict[str, str]:
    if not output_path.exists():
        return {}
    headers, rows = read_csv_rows(output_path, set(OUTPUT_HEADERS))
    if headers != list(OUTPUT_HEADERS):
        raise StorePublishingError("Existing Phase 6B review headers changed.")
    indexed = _index_unique(rows, "reviewItemId", "existing Phase 6B review")
    if set(indexed) != expected_ids:
        raise StorePublishingError("Existing Phase 6B review target set changed.")
    return {item_id: row.get("reviewerNote", "") for item_id, row in indexed.items()}


def build_25_store_expansion_review(
    publish_path: Path,
    style_path: Path,
    staging_path: Path,
    hold_path: Path,
    kakao_path: Path,
    candidate_path: Path,
    evidence_path: Path,
    output_path: Path,
) -> tuple[list[dict[str, str]], dict[str, int]]:
    protected_paths = (
        publish_path,
        style_path,
        staging_path,
        hold_path,
        kakao_path,
        candidate_path,
    )
    before_hashes = {path: file_sha256(path) for path in protected_paths}
    _, publish_rows = read_csv_rows(publish_path, PUBLISH_HEADERS)
    _, style_rows = read_csv_rows(style_path, STYLE_HEADERS)
    _, staging_rows = read_csv_rows(staging_path, STAGING_HEADERS)
    _, hold_rows = read_csv_rows(hold_path, HOLD_HEADERS)
    _, kakao_rows = read_csv_rows(kakao_path, KAKAO_HEADERS)
    _, candidate_rows = read_csv_rows(candidate_path, CANDIDATE_HEADERS)
    identities, public_count = _build_identities(
        publish_rows, style_rows, staging_rows, hold_rows, kakao_rows, candidate_rows
    )
    _, evidence_by_id = _load_evidence(evidence_path, identities)
    ids = {stable_review_item_id(row) for row in identities}
    notes = _preserved_notes(output_path, ids)

    output_rows: list[dict[str, str]] = []
    for identity in identities:
        item_id = stable_review_item_id(identity)
        evidence = evidence_by_id[item_id]
        sources = evidence["sources"]
        source1 = sources[0]
        source2 = sources[1] if len(sources) > 1 else {}
        output_rows.append(
            {
                "reviewItemId": item_id,
                **identity,
                "operatingStatusAssessment": evidence["operatingStatusAssessment"],
                "identityAssessment": evidence["identityAssessment"],
                "addressAssessment": evidence["addressAssessment"],
                "coordinateAssessment": evidence["coordinateAssessment"],
                "burgerSpecialtyAssessment": evidence["burgerSpecialtyAssessment"],
                "styleAssessment": evidence["styleAssessment"],
                "officialSourceAvailable": str(
                    evidence["officialSourceAvailable"]
                ).lower(),
                "evidenceCount": str(len(sources)),
                "recentEvidenceCount": str(evidence["recentEvidenceCount"]),
                "source1Type": source1["type"],
                "source1Title": source1["title"],
                "source1Url": source1["url"],
                "source1PublishedAt": source1["publishedAt"],
                "source2Type": source2.get("type", ""),
                "source2Title": source2.get("title", ""),
                "source2Url": source2.get("url", ""),
                "source2PublishedAt": source2.get("publishedAt", ""),
                "latestEvidenceAsOf": evidence["latestEvidenceAsOf"],
                "conflictStatus": evidence["conflictStatus"],
                "recommendedDecision": evidence["recommendedDecision"],
                "recommendationReason": evidence["recommendationReason"],
                "remainingRisk": evidence["remainingRisk"],
                "reviewerNote": notes.get(item_id, ""),
            }
        )

    recommendations = sum(
        row["recommendedDecision"] in READY_RECOMMENDATIONS for row in output_rows
    )
    if recommendations > MAX_RECOMMENDATIONS:
        raise StorePublishingError(
            f"At most {MAX_RECOMMENDATIONS} stores may be recommended."
        )
    if any(
        row["currentPublishDecision"] in {"verified", "rejected"}
        or row["currentIsActive"] != "false"
        for row in output_rows
    ):
        raise StorePublishingError("Phase 6B must not include or alter public/rejected rows.")

    write_csv_rows(output_path, OUTPUT_HEADERS, output_rows)
    after_hashes = {path: file_sha256(path) for path in protected_paths}
    if before_hashes != after_hashes:
        raise StorePublishingError("A protected input changed while building the review.")
    summary = {
        "public": public_count,
        "pending": sum(row["sourceGroup"] == "pending" for row in output_rows),
        "hold": sum(row["sourceGroup"] == "hold" for row in output_rows),
        "recommended": recommendations,
        "shortfall": max(0, TARGET_PUBLIC_STORES - public_count - recommendations),
    }
    return output_rows, summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish-review", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--style-review", type=Path, default=DEFAULT_STYLE_PATH)
    parser.add_argument("--staging", type=Path, default=DEFAULT_STAGING_PATH)
    parser.add_argument("--hold-report", type=Path, default=DEFAULT_HOLD_PATH)
    parser.add_argument("--kakao-review", type=Path, default=DEFAULT_KAKAO_PATH)
    parser.add_argument("--candidate-review", type=Path, default=DEFAULT_CANDIDATE_PATH)
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        rows, summary = build_25_store_expansion_review(
            args.publish_review,
            args.style_review,
            args.staging,
            args.hold_report,
            args.kakao_review,
            args.candidate_review,
            args.evidence,
            args.output,
        )
    except StorePublishingError as error:
        print(f"Review build failed: {error}", file=sys.stderr)
        return 1
    decisions = Counter(row["recommendedDecision"] for row in rows)
    print(
        f"Created {len(rows)} review rows: pending={summary['pending']}, "
        f"hold={summary['hold']}, recommended={summary['recommended']}, "
        f"shortfall={summary['shortfall']}."
    )
    print("Decision counts: " + ", ".join(f"{k}={v}" for k, v in sorted(decisions.items())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
