#!/usr/bin/env python3
"""Create or refresh the local human-review CSV for burger styles."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
import uuid
from collections import Counter
from pathlib import Path
from typing import Mapping, Sequence
from urllib.parse import urlparse


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from store_publishing_common import (  # noqa: E402
    StorePublishingError,
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
DEFAULT_HOLD_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_staging_hold_report.csv"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_style_review.csv"
)
EXPECTED_STAGING_ROWS = 24
EXPECTED_HOLD_ROWS = 4

B1_STYLE_REVIEW_HEADERS = (
    "reviewNumber",
    "storeId",
    "candidateId",
    "name",
    "address",
    "currentBurgerStyle",
    "proposedBurgerStyle",
    "reviewStatus",
    "confidence",
    "evidenceSourceType",
    "evidenceSourceName",
    "evidenceUrl",
    "evidenceCheckedAt",
    "evidenceNote",
    "reviewerNote",
)
STYLE_REVIEW_HEADERS = (
    *B1_STYLE_REVIEW_HEADERS,
    "secondaryEvidenceSourceType",
    "secondaryEvidenceSourceName",
    "secondaryEvidenceUrl",
    "sourceAgreement",
    "freshnessNote",
    "approvalRecommendation",
)
LEGACY_STYLE_REVIEW_HEADERS = (
    *B1_STYLE_REVIEW_HEADERS[:5],
    "latitude",
    "longitude",
    *B1_STYLE_REVIEW_HEADERS[5:],
)
EDITABLE_REVIEW_FIELDS = STYLE_REVIEW_HEADERS[6:]
ALLOWED_STYLES = {
    "classic",
    "smash",
    "chicken",
    "plant_based",
    "other",
    "unclassified",
}
STYLE_ALIASES = {
    "classic": "classic",
    "클래식": "classic",
    "smash": "smash",
    "스매시": "smash",
    "chicken": "chicken",
    "치킨": "chicken",
    "plant_based": "plant_based",
    "비건·식물성": "plant_based",
    "비건": "plant_based",
    "식물성": "plant_based",
    "other": "other",
    "기타": "other",
    "unclassified": "unclassified",
    "미분류": "unclassified",
}
ALLOWED_REVIEW_STATUSES = {"proposed", "needs_recheck", "approved"}
ALLOWED_CONFIDENCE = {"high", "medium", "low"}
ALLOWED_EVIDENCE_SOURCE_TYPES = {
    "official_menu",
    "official_website",
    "official_social",
    "place_platform",
    "article",
    "other",
}
OFFICIAL_EVIDENCE_SOURCE_TYPES = {
    "official_menu",
    "official_website",
    "official_social",
}
ALLOWED_SOURCE_AGREEMENTS = {
    "consistent",
    "conflict",
    "single_source",
    "unavailable",
}
ALLOWED_APPROVAL_RECOMMENDATIONS = {
    "ready_for_user_approval",
    "needs_manual_check",
}
LEGACY_EVIDENCE_SOURCE_TYPE_ALIASES = {
    "public_menu_page": "place_platform",
    "public_place_page": "place_platform",
    "public_social_mirror": "other",
    "reliable_secondary": "article",
    "public_record": "other",
}
STAGING_REQUIRED_HEADERS = {
    "candidateId",
    "displayName",
    "address",
    "latitude",
    "longitude",
    "stagingStatus",
    "verificationStatus",
}
PUBLISH_REQUIRED_HEADERS = {
    "storeId",
    "candidateId",
    "name",
    "address",
    "latitude",
    "longitude",
    "burgerStyle",
}
HOLD_REQUIRED_HEADERS = {"candidateId", "name", "stagingStatus"}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalize_burger_style(value: str | None) -> str:
    normalized = (value or "").strip().casefold()
    return STYLE_ALIASES.get(normalized, "unclassified")


def _index_unique(
    rows: Sequence[Mapping[str, str]],
    id_field: str,
    source_label: str,
) -> dict[str, Mapping[str, str]]:
    indexed: dict[str, Mapping[str, str]] = {}
    for row in rows:
        row_id = row.get(id_field, "").strip()
        if not row_id or row_id in indexed:
            raise StorePublishingError(
                f"{source_label} {id_field}가 비었거나 중복됐습니다: {row_id}"
            )
        indexed[row_id] = row
    return indexed


def _validated_uuid(value: str, candidate_id: str) -> str:
    try:
        return str(uuid.UUID(value.strip()))
    except ValueError:
        raise StorePublishingError(
            f"게시 검수표 storeId가 UUID가 아닙니다: {candidate_id}"
        ) from None


def _validate_review_fields(row: Mapping[str, str], candidate_id: str) -> None:
    style = row.get("proposedBurgerStyle", "").strip()
    status = row.get("reviewStatus", "").strip()
    confidence = row.get("confidence", "").strip()
    evidence_source_type = row.get("evidenceSourceType", "").strip()
    secondary_source_type = row.get("secondaryEvidenceSourceType", "").strip()
    source_agreement = row.get("sourceAgreement", "").strip()
    approval_recommendation = row.get("approvalRecommendation", "").strip()
    if style not in ALLOWED_STYLES:
        raise StorePublishingError(
            f"허용되지 않은 proposedBurgerStyle입니다: {candidate_id}, {style}"
        )
    if status not in ALLOWED_REVIEW_STATUSES:
        raise StorePublishingError(
            f"허용되지 않은 reviewStatus입니다: {candidate_id}, {status}"
        )
    if confidence not in ALLOWED_CONFIDENCE:
        raise StorePublishingError(
            f"허용되지 않은 confidence입니다: {candidate_id}, {confidence}"
        )
    if evidence_source_type and evidence_source_type not in ALLOWED_EVIDENCE_SOURCE_TYPES:
        raise StorePublishingError(
            f"허용되지 않은 evidenceSourceType입니다: "
            f"{candidate_id}, {evidence_source_type}"
        )
    if (
        secondary_source_type
        and secondary_source_type not in ALLOWED_EVIDENCE_SOURCE_TYPES
    ):
        raise StorePublishingError(
            f"허용되지 않은 secondaryEvidenceSourceType입니다: "
            f"{candidate_id}, {secondary_source_type}"
        )
    if source_agreement not in ALLOWED_SOURCE_AGREEMENTS:
        raise StorePublishingError(
            f"허용되지 않은 sourceAgreement입니다: "
            f"{candidate_id}, {source_agreement}"
        )
    if approval_recommendation not in ALLOWED_APPROVAL_RECOMMENDATIONS:
        raise StorePublishingError(
            f"허용되지 않은 approvalRecommendation입니다: "
            f"{candidate_id}, {approval_recommendation}"
        )
    if confidence == "low" and status != "needs_recheck":
        raise StorePublishingError(
            f"low confidence는 needs_recheck여야 합니다: {candidate_id}"
        )
    if status == "needs_recheck" and (
        style != "unclassified" or confidence != "low"
    ):
        raise StorePublishingError(
            f"needs_recheck는 unclassified + low여야 합니다: {candidate_id}"
        )
    if style == "unclassified" and status != "needs_recheck":
        raise StorePublishingError(f"미분류는 needs_recheck여야 합니다: {candidate_id}")
    if source_agreement in {"single_source", "conflict", "unavailable"} and status in {
        "proposed",
        "approved",
    }:
        raise StorePublishingError(
            f"교차 검증되지 않은 행은 proposed 또는 approved일 수 없습니다: "
            f"{candidate_id}"
        )
    if approval_recommendation == "needs_manual_check" and status != "needs_recheck":
        raise StorePublishingError(
            f"needs_manual_check는 needs_recheck여야 합니다: {candidate_id}"
        )
    if approval_recommendation == "ready_for_user_approval" and status not in {
        "proposed",
        "approved",
    }:
        raise StorePublishingError(
            f"ready_for_user_approval 상태가 올바르지 않습니다: {candidate_id}"
        )
    if status == "approved" and not row.get("reviewerNote", "").strip():
        raise StorePublishingError(
            f"사용자 승인 메모 없는 approved는 허용되지 않습니다: {candidate_id}"
        )
    if status in {"proposed", "approved"}:
        required_evidence = (
            "evidenceSourceType",
            "evidenceSourceName",
            "evidenceUrl",
            "evidenceCheckedAt",
            "evidenceNote",
        )
        missing = [field for field in required_evidence if not row.get(field, "").strip()]
        if missing:
            raise StorePublishingError(
                f"제안 또는 승인 행의 근거가 누락됐습니다: {candidate_id}, {missing}"
            )
        if source_agreement != "consistent":
            raise StorePublishingError(
                f"제안 또는 승인 행은 출처가 일치해야 합니다: {candidate_id}"
            )
        if evidence_source_type not in OFFICIAL_EVIDENCE_SOURCE_TYPES:
            secondary_required = (
                "secondaryEvidenceSourceType",
                "secondaryEvidenceSourceName",
                "secondaryEvidenceUrl",
            )
            missing_secondary = [
                field for field in secondary_required if not row.get(field, "").strip()
            ]
            if missing_secondary:
                raise StorePublishingError(
                    f"비공식 제안 행의 독립 2차 근거가 누락됐습니다: "
                    f"{candidate_id}, {missing_secondary}"
                )
    checked_at = row.get("evidenceCheckedAt", "").strip()
    if checked_at:
        try:
            dt.date.fromisoformat(checked_at)
        except ValueError:
            raise StorePublishingError(
                f"evidenceCheckedAt이 YYYY-MM-DD가 아닙니다: {candidate_id}"
            ) from None
    evidence_url = row.get("evidenceUrl", "").strip()
    secondary_evidence_url = row.get("secondaryEvidenceUrl", "").strip()
    for url_field, url_value in (
        ("evidenceUrl", evidence_url),
        ("secondaryEvidenceUrl", secondary_evidence_url),
    ):
        if not url_value:
            continue
        parsed_url = urlparse(url_value)
        if parsed_url.scheme not in {"http", "https"} or not parsed_url.netloc:
            raise StorePublishingError(
                f"{url_field}이 유효하지 않습니다: {candidate_id}"
            )
    secondary_values = (
        secondary_source_type,
        row.get("secondaryEvidenceSourceName", "").strip(),
        secondary_evidence_url,
    )
    if any(secondary_values) and not all(secondary_values):
        raise StorePublishingError(
            f"2차 근거 필드는 모두 입력해야 합니다: {candidate_id}"
        )
    if evidence_url and secondary_evidence_url and evidence_url == secondary_evidence_url:
        raise StorePublishingError(
            f"1차와 2차 근거 URL이 같습니다: {candidate_id}"
        )


def _load_existing_review(path: Path) -> tuple[list[str], dict[str, dict[str, str]]]:
    if not path.exists():
        return [], {}
    headers, rows = read_csv_rows(path, set(B1_STYLE_REVIEW_HEADERS))
    if headers not in (
        list(STYLE_REVIEW_HEADERS),
        list(B1_STYLE_REVIEW_HEADERS),
        list(LEGACY_STYLE_REVIEW_HEADERS),
    ):
        raise StorePublishingError("기존 스타일 검수표 컬럼 또는 순서가 다릅니다.")
    indexed = _index_unique(rows, "candidateId", "기존 스타일 검수표")
    for candidate_id, row in indexed.items():
        source_type = row.get("evidenceSourceType", "").strip()
        if source_type in LEGACY_EVIDENCE_SOURCE_TYPE_ALIASES:
            row["evidenceSourceType"] = LEGACY_EVIDENCE_SOURCE_TYPE_ALIASES[
                source_type
            ]
        if headers != list(STYLE_REVIEW_HEADERS):
            previous_style = row.get("proposedBurgerStyle", "").strip()
            previous_status = row.get("reviewStatus", "").strip()
            existing_note = row.get("reviewerNote", "").strip()
            migration_note = (
                "B1R 스키마 전환: 독립 출처 교차 검증 전 안전하게 재확인으로 전환"
            )
            if previous_status == "proposed":
                migration_note += f"(이전 제안: {previous_style})"
                row["proposedBurgerStyle"] = "unclassified"
                row["reviewStatus"] = "needs_recheck"
                row["confidence"] = "low"
            row.update(
                {
                    "secondaryEvidenceSourceType": "",
                    "secondaryEvidenceSourceName": "",
                    "secondaryEvidenceUrl": "",
                    "sourceAgreement": "single_source"
                    if row.get("evidenceUrl", "").strip()
                    else "unavailable",
                    "freshnessNote": "B1R 전환 시점에 1차 근거만 기록됨.",
                    "approvalRecommendation": "needs_manual_check",
                    "reviewerNote": "; ".join(
                        note for note in (existing_note, migration_note) if note
                    ),
                }
            )
        _validate_review_fields(row, candidate_id)
    return [row["candidateId"].strip() for row in rows], {
        candidate_id: dict(row) for candidate_id, row in indexed.items()
    }


def validate_style_review_rows(
    rows: Sequence[Mapping[str, str]],
) -> list[dict[str, str]]:
    """Validate current-schema rows and return independent dictionaries."""
    seen_review_numbers: set[str] = set()
    seen_store_ids: set[str] = set()
    seen_candidate_ids: set[str] = set()
    output: list[dict[str, str]] = []
    for expected_number, raw_row in enumerate(rows, start=1):
        row = dict(raw_row)
        review_number = row.get("reviewNumber", "").strip()
        candidate_id = row.get("candidateId", "").strip()
        store_id = _validated_uuid(row.get("storeId", ""), candidate_id)
        if review_number != str(expected_number):
            raise StorePublishingError(
                f"스타일 검수표 행 순서가 올바르지 않습니다: {review_number}"
            )
        if review_number in seen_review_numbers:
            raise StorePublishingError(
                f"reviewNumber가 중복됐습니다: {review_number}"
            )
        if not candidate_id or candidate_id in seen_candidate_ids:
            raise StorePublishingError(
                f"candidateId가 비었거나 중복됐습니다: {candidate_id}"
            )
        if store_id in seen_store_ids:
            raise StorePublishingError(f"storeId가 중복됐습니다: {candidate_id}")
        if not row.get("name", "").strip() or not row.get("address", "").strip():
            raise StorePublishingError(f"이름 또는 주소가 비었습니다: {candidate_id}")
        _validate_review_fields(row, candidate_id)
        seen_review_numbers.add(review_number)
        seen_store_ids.add(store_id)
        seen_candidate_ids.add(candidate_id)
        output.append(row)
    return output


def read_validated_style_review_rows(path: Path) -> list[dict[str, str]]:
    """Read a current-schema style review without changing or migrating it."""
    headers, rows = read_csv_rows(path, set(STYLE_REVIEW_HEADERS))
    if headers != list(STYLE_REVIEW_HEADERS):
        raise StorePublishingError("스타일 검수표 컬럼 또는 순서가 다릅니다.")
    return validate_style_review_rows(rows)


def build_style_review_rows(
    staging_rows: Sequence[Mapping[str, str]],
    publish_rows: Sequence[Mapping[str, str]],
    hold_rows: Sequence[Mapping[str, str]],
    existing_order: Sequence[str],
    existing_by_candidate: Mapping[str, Mapping[str, str]],
) -> list[dict[str, str]]:
    if len(staging_rows) != EXPECTED_STAGING_ROWS:
        raise StorePublishingError(
            f"staging 행 수가 정확히 24개가 아닙니다: {len(staging_rows)}"
        )
    if len(publish_rows) != EXPECTED_STAGING_ROWS:
        raise StorePublishingError(
            f"게시 검수표 행 수가 정확히 24개가 아닙니다: {len(publish_rows)}"
        )
    if len(hold_rows) != EXPECTED_HOLD_ROWS:
        raise StorePublishingError(
            f"hold report 행 수가 정확히 4개가 아닙니다: {len(hold_rows)}"
        )

    staging_by_candidate = _index_unique(
        staging_rows, "candidateId", "staging"
    )
    publish_by_candidate = _index_unique(
        publish_rows, "candidateId", "게시 검수표"
    )
    hold_by_candidate = _index_unique(hold_rows, "candidateId", "hold report")
    staging_ids = set(staging_by_candidate)
    if staging_ids != set(publish_by_candidate):
        raise StorePublishingError("staging과 게시 검수표의 candidateId 집합이 다릅니다.")
    if staging_ids & set(hold_by_candidate):
        raise StorePublishingError("보류 candidateId가 스타일 검수 대상에 포함됐습니다.")
    hold_names = {row.get("name", "").strip() for row in hold_rows}
    if any(row.get("displayName", "").strip() in hold_names for row in staging_rows):
        raise StorePublishingError("보류 매장명이 스타일 검수 대상에 포함됐습니다.")
    if existing_by_candidate:
        if set(existing_by_candidate) != staging_ids:
            raise StorePublishingError(
                "기존 스타일 검수표와 staging의 candidateId 집합이 다릅니다."
            )
        staging_order = [row["candidateId"].strip() for row in staging_rows]
        if list(existing_order) != staging_order:
            raise StorePublishingError("기존 스타일 검수표의 행 순서가 변경됐습니다.")

    output: list[dict[str, str]] = []
    seen_store_ids: set[str] = set()
    for index, staging_row in enumerate(staging_rows, start=1):
        candidate_id = staging_row.get("candidateId", "").strip()
        name = staging_row.get("displayName", "").strip()
        address = staging_row.get("address", "").strip()
        if not name or not address:
            raise StorePublishingError(f"이름 또는 주소가 비었습니다: {candidate_id}")
        if staging_row.get("stagingStatus", "").strip() != "candidate_pending":
            raise StorePublishingError(f"staging 상태가 올바르지 않습니다: {candidate_id}")
        if staging_row.get("verificationStatus", "").strip() != "pending":
            raise StorePublishingError(f"pending 매장이 아닙니다: {candidate_id}")
        parse_coordinate(staging_row.get("latitude", ""), "latitude", candidate_id)
        parse_coordinate(staging_row.get("longitude", ""), "longitude", candidate_id)

        publish_row = publish_by_candidate[candidate_id]
        store_id = _validated_uuid(publish_row.get("storeId", ""), candidate_id)
        if store_id in seen_store_ids:
            raise StorePublishingError(f"storeId가 중복됐습니다: {candidate_id}")
        seen_store_ids.add(store_id)
        immutable_pairs = {
            "name": name,
            "address": address,
            "latitude": staging_row.get("latitude", "").strip(),
            "longitude": staging_row.get("longitude", "").strip(),
        }
        changed_publish_fields = [
            field
            for field, expected in immutable_pairs.items()
            if publish_row.get(field, "").strip() != expected
        ]
        if changed_publish_fields:
            raise StorePublishingError(
                f"게시 검수표 원본 필드가 staging과 다릅니다: "
                f"{candidate_id}, {changed_publish_fields}"
            )
        current_style = normalize_burger_style(publish_row.get("burgerStyle", ""))
        existing = existing_by_candidate.get(candidate_id)
        if existing is None:
            editable = {
                "proposedBurgerStyle": "unclassified",
                "reviewStatus": "needs_recheck",
                "confidence": "low",
                "evidenceSourceType": "",
                "evidenceSourceName": "",
                "evidenceUrl": "",
                "evidenceCheckedAt": "",
                "evidenceNote": "",
                "reviewerNote": "",
                "secondaryEvidenceSourceType": "",
                "secondaryEvidenceSourceName": "",
                "secondaryEvidenceUrl": "",
                "sourceAgreement": "unavailable",
                "freshnessNote": "",
                "approvalRecommendation": "needs_manual_check",
            }
        else:
            expected_existing = {
                "reviewNumber": str(index),
                "storeId": store_id,
                "name": name,
                "address": address,
                "currentBurgerStyle": current_style,
            }
            if "latitude" in existing or "longitude" in existing:
                expected_existing.update(
                    {
                        "latitude": immutable_pairs["latitude"],
                        "longitude": immutable_pairs["longitude"],
                    }
                )
            changed_existing_fields = [
                field
                for field, expected in expected_existing.items()
                if existing.get(field, "").strip() != expected
            ]
            if changed_existing_fields:
                raise StorePublishingError(
                    f"기존 스타일 검수표의 불변 필드가 변경됐습니다: "
                    f"{candidate_id}, {changed_existing_fields}"
                )
            editable = {
                field: existing.get(field, "").strip()
                for field in EDITABLE_REVIEW_FIELDS
            }
            _validate_review_fields(editable, candidate_id)
        row = {
            "reviewNumber": str(index),
            "storeId": store_id,
            "candidateId": candidate_id,
            "name": name,
            "address": address,
            "currentBurgerStyle": current_style,
            **editable,
        }
        _validate_review_fields(row, candidate_id)
        output.append(row)
    return output


def generate_style_review(
    staging_path: Path,
    publish_review_path: Path,
    hold_path: Path,
    output_path: Path,
) -> list[dict[str, str]]:
    input_paths = (staging_path, publish_review_path, hold_path)
    if output_path.resolve() in {path.resolve() for path in input_paths}:
        raise StorePublishingError("스타일 검수표 출력은 입력 파일과 달라야 합니다.")
    hashes_before = {path.resolve(): file_sha256(path) for path in input_paths}
    _, staging_rows = read_csv_rows(staging_path, STAGING_REQUIRED_HEADERS)
    _, publish_rows = read_csv_rows(publish_review_path, PUBLISH_REQUIRED_HEADERS)
    _, hold_rows = read_csv_rows(hold_path, HOLD_REQUIRED_HEADERS)
    existing_order, existing = _load_existing_review(output_path)
    output = build_style_review_rows(
        staging_rows,
        publish_rows,
        hold_rows,
        existing_order,
        existing,
    )
    hashes_after = {path.resolve(): file_sha256(path) for path in input_paths}
    if hashes_before != hashes_after:
        raise StorePublishingError("입력 CSV 해시가 생성 전후 달라졌습니다.")
    write_csv_rows(output_path, STYLE_REVIEW_HEADERS, output)
    return output


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="버거 스타일 사람 검수표를 생성합니다.")
    parser.add_argument("--staging", type=Path, default=DEFAULT_STAGING_PATH)
    parser.add_argument(
        "--publish-review", type=Path, default=DEFAULT_PUBLISH_REVIEW_PATH
    )
    parser.add_argument("--hold-report", type=Path, default=DEFAULT_HOLD_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows = generate_style_review(
            args.staging,
            args.publish_review,
            args.hold_report,
            args.output,
        )
        print(
            json.dumps(
                {
                    "reviewRows": len(rows),
                    "reviewStatuses": dict(
                        sorted(Counter(row["reviewStatus"] for row in rows).items())
                    ),
                    "proposedStyles": dict(
                        sorted(
                            Counter(
                                row["proposedBurgerStyle"] for row in rows
                            ).items()
                        )
                    ),
                    "approvedRows": sum(
                        row["reviewStatus"] == "approved" for row in rows
                    ),
                    "outputPath": str(args.output.resolve()),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except StorePublishingError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
