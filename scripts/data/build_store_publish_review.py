#!/usr/bin/env python3
"""Create or refresh the local human-review CSV for store publishing."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import uuid
from collections import Counter
from pathlib import Path
from typing import Callable, Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from store_publishing_common import (  # noqa: E402
    REVIEW_HEADERS,
    StorePublishingError,
    parse_coordinate,
    parse_store_schema,
    read_csv_rows,
    write_csv_rows,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_STAGING_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_stores_staging.csv"
)
DEFAULT_HOLD_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_staging_hold_report.csv"
)
DEFAULT_MIGRATION_PATH = (
    PROJECT_ROOT / "supabase" / "migrations" / "0001_init_store_schema.sql"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_store_publish_review.csv"
)
EXPECTED_STAGING_ROWS = 24
EXPECTED_HOLD_ROWS = 4
STAGING_REQUIRED_HEADERS = {
    "candidateId",
    "displayName",
    "address",
    "latitude",
    "longitude",
    "stagingStatus",
    "sourceType",
    "verificationStatus",
}
HOLD_REQUIRED_HEADERS = {"candidateId", "name", "stagingStatus"}
SOURCE_TYPE_MAP = {
    "semas_kakao": "mixed",
    "kakao": "manual_review",
}
EDITABLE_REVIEW_FIELDS = (
    "burgerStyle",
    "sourceAsOf",
    "publishDecision",
    "isActive",
    "verifiedAt",
    "verificationNote",
)


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _index_existing_review(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    headers, rows = read_csv_rows(path, set(REVIEW_HEADERS))
    if headers != list(REVIEW_HEADERS):
        raise StorePublishingError("기존 게시 검수표 컬럼 또는 순서가 다릅니다.")
    indexed: dict[str, dict[str, str]] = {}
    for row in rows:
        candidate_id = row["candidateId"].strip()
        if not candidate_id or candidate_id in indexed:
            raise StorePublishingError("기존 검수표 candidateId가 비었거나 중복됐습니다.")
        try:
            canonical_store_id = str(uuid.UUID(row["storeId"].strip()))
        except ValueError:
            raise StorePublishingError(
                f"기존 검수표 storeId가 UUID가 아닙니다: {candidate_id}"
            ) from None
        row["storeId"] = canonical_store_id
        indexed[candidate_id] = row
    if len({row["storeId"] for row in indexed.values()}) != len(indexed):
        raise StorePublishingError("기존 검수표 storeId가 중복됐습니다.")
    return indexed


def _validate_staging_row(row: Mapping[str, str], seen_ids: set[str]) -> None:
    candidate_id = row.get("candidateId", "").strip()
    name = row.get("displayName", "").strip()
    address = row.get("address", "").strip()
    if not candidate_id or candidate_id in seen_ids:
        raise StorePublishingError(
            f"staging candidateId가 비었거나 중복됐습니다: {candidate_id}"
        )
    if not name or not address:
        raise StorePublishingError(f"staging 이름 또는 주소가 비었습니다: {candidate_id}")
    if row.get("stagingStatus", "").strip() != "candidate_pending":
        raise StorePublishingError(f"게시 검수 대상이 아닌 staging 행입니다: {candidate_id}")
    if row.get("verificationStatus", "").strip() != "pending":
        raise StorePublishingError(f"pending이 아닌 staging 행입니다: {candidate_id}")
    if row.get("sourceType", "").strip() not in SOURCE_TYPE_MAP:
        raise StorePublishingError(f"알 수 없는 staging sourceType입니다: {candidate_id}")
    parse_coordinate(row.get("latitude", ""), "latitude", candidate_id)
    parse_coordinate(row.get("longitude", ""), "longitude", candidate_id)


def build_review_rows(
    staging_rows: Sequence[Mapping[str, str]],
    hold_rows: Sequence[Mapping[str, str]],
    existing_by_candidate: Mapping[str, Mapping[str, str]],
    allowed_source_types: set[str] | frozenset[str],
    *,
    uuid_factory: Callable[[], uuid.UUID] = uuid.uuid4,
) -> list[dict[str, str]]:
    if len(staging_rows) != EXPECTED_STAGING_ROWS:
        raise StorePublishingError(
            f"staging 행 수가 정확히 24개가 아닙니다: {len(staging_rows)}"
        )
    if len(hold_rows) != EXPECTED_HOLD_ROWS:
        raise StorePublishingError(
            f"hold report 행 수가 정확히 4개가 아닙니다: {len(hold_rows)}"
        )
    hold_ids: set[str] = set()
    hold_names: set[str] = set()
    for row in hold_rows:
        candidate_id = row.get("candidateId", "").strip()
        name = row.get("name", "").strip()
        if (
            not candidate_id
            or candidate_id in hold_ids
            or not name
            or row.get("stagingStatus", "").strip() != "hold_needs_recheck"
        ):
            raise StorePublishingError("hold report 값이 비었거나 중복·상태 오류가 있습니다.")
        hold_ids.add(candidate_id)
        hold_names.add(name)

    staging_ids = {row.get("candidateId", "").strip() for row in staging_rows}
    if staging_ids & hold_ids:
        raise StorePublishingError("보류 candidateId가 staging 게시 검수 대상에 포함됐습니다.")
    staging_names = {row.get("displayName", "").strip() for row in staging_rows}
    if staging_names & hold_names:
        raise StorePublishingError("보류 매장명이 staging 게시 검수 대상에 포함됐습니다.")
    if existing_by_candidate and set(existing_by_candidate) != staging_ids:
        raise StorePublishingError("기존 검수표와 staging의 candidateId 집합이 다릅니다.")

    output: list[dict[str, str]] = []
    seen_ids: set[str] = set()
    seen_store_ids: set[str] = set()
    for staging_row in staging_rows:
        _validate_staging_row(staging_row, seen_ids)
        candidate_id = staging_row["candidateId"].strip()
        source_type = SOURCE_TYPE_MAP[staging_row["sourceType"].strip()]
        if source_type not in allowed_source_types:
            raise StorePublishingError(
                f"migration에서 허용하지 않는 sourceType입니다: {candidate_id}"
            )
        existing = existing_by_candidate.get(candidate_id)
        if existing is None:
            store_id = str(uuid_factory())
            editable = {
                "burgerStyle": "",
                "sourceAsOf": "",
                "publishDecision": "pending",
                "isActive": "false",
                "verifiedAt": "",
                "verificationNote": "",
            }
        else:
            immutable_pairs = {
                "name": staging_row["displayName"].strip(),
                "address": staging_row["address"].strip(),
                "latitude": staging_row["latitude"].strip(),
                "longitude": staging_row["longitude"].strip(),
                "sourceType": source_type,
            }
            changed = [
                field
                for field, expected in immutable_pairs.items()
                if existing.get(field, "").strip() != expected
            ]
            if changed:
                raise StorePublishingError(
                    f"기존 검수표의 원본 필드가 staging과 다릅니다: "
                    f"{candidate_id}, {changed}"
                )
            store_id = existing["storeId"].strip()
            editable = {
                field: existing.get(field, "").strip()
                for field in EDITABLE_REVIEW_FIELDS
            }
        try:
            store_id = str(uuid.UUID(store_id))
        except ValueError:
            raise StorePublishingError(f"storeId가 UUID가 아닙니다: {candidate_id}") from None
        if store_id in seen_store_ids:
            raise StorePublishingError(f"storeId가 중복됐습니다: {candidate_id}")
        output.append(
            {
                "storeId": store_id,
                "candidateId": candidate_id,
                "name": staging_row["displayName"].strip(),
                "address": staging_row["address"].strip(),
                "latitude": staging_row["latitude"].strip(),
                "longitude": staging_row["longitude"].strip(),
                "burgerStyle": editable["burgerStyle"],
                "sourceType": source_type,
                "sourceAsOf": editable["sourceAsOf"],
                "publishDecision": editable["publishDecision"],
                "isActive": editable["isActive"],
                "verifiedAt": editable["verifiedAt"],
                "verificationNote": editable["verificationNote"],
            }
        )
        seen_ids.add(candidate_id)
        seen_store_ids.add(store_id)
    return output


def generate_publish_review(
    staging_path: Path,
    hold_path: Path,
    migration_path: Path,
    output_path: Path,
    *,
    uuid_factory: Callable[[], uuid.UUID] = uuid.uuid4,
) -> list[dict[str, str]]:
    input_paths = (staging_path.resolve(), hold_path.resolve(), migration_path.resolve())
    if output_path.resolve() in input_paths:
        raise StorePublishingError("검수표 출력은 입력 파일과 달라야 합니다.")
    hashes_before = {path: file_sha256(path) for path in (staging_path, hold_path)}
    _, staging_rows = read_csv_rows(staging_path, STAGING_REQUIRED_HEADERS)
    _, hold_rows = read_csv_rows(hold_path, HOLD_REQUIRED_HEADERS)
    schema = parse_store_schema(migration_path)
    existing = _index_existing_review(output_path)
    output = build_review_rows(
        staging_rows,
        hold_rows,
        existing,
        schema.source_types,
        uuid_factory=uuid_factory,
    )
    write_csv_rows(output_path, REVIEW_HEADERS, output)
    hashes_after = {path: file_sha256(path) for path in (staging_path, hold_path)}
    if hashes_before != hashes_after:
        raise StorePublishingError("입력 CSV 해시가 생성 전후 달라졌습니다.")
    return output


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="게시 전 사람 검수용 CSV를 생성합니다.")
    parser.add_argument("--staging", type=Path, default=DEFAULT_STAGING_PATH)
    parser.add_argument("--hold-report", type=Path, default=DEFAULT_HOLD_PATH)
    parser.add_argument("--migration", type=Path, default=DEFAULT_MIGRATION_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows = generate_publish_review(
            args.staging,
            args.hold_report,
            args.migration,
            args.output,
        )
        print(
            json.dumps(
                {
                    "reviewRows": len(rows),
                    "publishDecisions": dict(
                        sorted(Counter(row["publishDecision"] for row in rows).items())
                    ),
                    "activeRows": sum(row["isActive"] == "true" for row in rows),
                    "uniqueStoreIds": len({row["storeId"] for row in rows}),
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
