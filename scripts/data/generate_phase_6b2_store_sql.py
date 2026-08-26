#!/usr/bin/env python3
"""Generate guarded INSERT SQL for the two Phase 6B-2 approvals.

If the output already exists, identical content is accepted. Different content
is never allowed to overwrite the existing SQL file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from apply_phase_6b2_store_approvals import (  # noqa: E402
    DEFAULT_APPROVAL_PATH,
    DEFAULT_PUBLISH_PATH,
    EXPECTED_APPROVALS,
    EXPECTED_FINAL_PUBLIC,
    EXPECTED_INITIAL_PUBLIC,
    file_sha256,
    load_phase_6b2_approval_manifest,
)
from generate_store_publish_sql import _sql_value, _validate_review_rows  # noqa: E402
from store_publishing_common import (  # noqa: E402
    REVIEW_HEADERS,
    STORE_INSERT_COLUMNS,
    StorePublishingError,
    normalize_store_text,
    parse_store_schema,
    read_csv_rows,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_MIGRATION_PATH = (
    PROJECT_ROOT / "supabase" / "migrations" / "0001_init_store_schema.sql"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "staging"
    / "yongsan_burger_store_publish_phase_6b2.sql"
)

FORBIDDEN_SQL_PATTERNS = {
    "internal approval or source identifier": re.compile(
        r"(?:candidateId|sourcePlaceId|discoveryId|reviewItemId|semas_|kakao_)",
        re.IGNORECASE,
    ),
    "external place data": re.compile(
        r"(?:source_place_id|place_url|kakao_place_id|google_place_id|https?://)",
        re.IGNORECASE,
    ),
    "credential": re.compile(
        r"(?:AIza[0-9A-Za-z_-]{30,}|sb_(?:publishable|secret)_[0-9A-Za-z_-]{20,}|"
        r"eyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+|"
        r"https://[a-z0-9]{15,}\.supabase\.co)",
        re.IGNORECASE,
    ),
    "forbidden write operation": re.compile(
        r"\b(?:update|delete|upsert|rpc)\b|on\s+conflict", re.IGNORECASE
    ),
}


def _sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _expected_row_sql(row: Mapping[str, object]) -> str:
    return (
        f"({_sql_text(str(row['id']))}::uuid, "
        f"{_sql_text(str(row['name']))}::text, "
        f"{_sql_text(str(row['address']))}::text, "
        f"{row['latitude']}::double precision, "
        f"{row['longitude']}::double precision, "
        f"{_sql_text(str(row['burger_style']))}::text, "
        f"{_sql_text(str(row['source_type']))}::text, "
        f"{_sql_text(row['source_as_of'].isoformat())}::date, "
        f"{_sql_text(row['verified_at'].isoformat())}::timestamptz)"
    )


def build_guarded_phase_6b2_sql(rows: Sequence[Mapping[str, object]]) -> str:
    if len(rows) != EXPECTED_APPROVALS:
        raise StorePublishingError("Phase 6B-2 INSERT 대상은 정확히 2곳이어야 합니다.")
    ids = [str(row["id"]) for row in rows]
    if len(ids) != len(set(ids)):
        raise StorePublishingError("Phase 6B-2 INSERT UUID가 중복됐습니다.")

    id_list = ",\n      ".join(f"{_sql_text(store_id)}::uuid" for store_id in ids)
    target_pairs = ",\n      ".join(
        f"({_sql_text(str(row['name']))}::text, {_sql_text(str(row['address']))}::text)"
        for row in rows
    )
    columns = ",\n      ".join(STORE_INSERT_COLUMNS)
    values = []
    for row in rows:
        row_values = ",\n        ".join(
            _sql_value(column, row[column]) for column in STORE_INSERT_COLUMNS
        )
        values.append(f"      (\n        {row_values}\n      )")
    expected_values = ",\n        ".join(_expected_row_sql(row) for row in rows)

    sql = (
        "begin;\n\n"
        "do $phase_6b2$\n"
        "declare\n"
        "  public_count integer;\n"
        "  existing_uuid_count integer;\n"
        "  duplicate_identity_count integer;\n"
        "  inserted_count integer;\n"
        "  matched_count integer;\n"
        "begin\n"
        "  select count(*) into public_count\n"
        "    from public.stores\n"
        "   where verification_status = 'verified' and is_active = true;\n"
        f"  if public_count <> {EXPECTED_INITIAL_PUBLIC} then\n"
        "    raise exception 'Phase 6B-2 precondition failed: expected 23 public stores.';\n"
        "  end if;\n\n"
        "  select count(*) into existing_uuid_count\n"
        "    from public.stores\n"
        "   where id in (\n"
        f"      {id_list}\n"
        "   );\n"
        "  if existing_uuid_count <> 0 then\n"
        "    raise exception 'Phase 6B-2 precondition failed: a new UUID already exists.';\n"
        "  end if;\n\n"
        "  select count(*) into duplicate_identity_count\n"
        "    from public.stores as store\n"
        "    join (values\n"
        f"      {target_pairs}\n"
        "    ) as target(name, address)\n"
        "      on lower(regexp_replace(store.name, '\\s+', '', 'g')) =\n"
        "         lower(regexp_replace(target.name, '\\s+', '', 'g'))\n"
        "     and lower(regexp_replace(store.address, '\\s+', '', 'g')) =\n"
        "         lower(regexp_replace(target.address, '\\s+', '', 'g'));\n"
        "  if duplicate_identity_count <> 0 then\n"
        "    raise exception 'Phase 6B-2 precondition failed: duplicate name and address.';\n"
        "  end if;\n\n"
        "  insert into public.stores (\n"
        f"      {columns}\n"
        "  ) values\n"
        + ",\n".join(values)
        + ";\n\n"
        "  get diagnostics inserted_count = row_count;\n"
        f"  if inserted_count <> {EXPECTED_APPROVALS} then\n"
        "    raise exception 'Phase 6B-2 insert count check failed.';\n"
        "  end if;\n\n"
        "  select count(*) into public_count\n"
        "    from public.stores\n"
        "   where verification_status = 'verified' and is_active = true;\n"
        f"  if public_count <> {EXPECTED_FINAL_PUBLIC} then\n"
        "    raise exception 'Phase 6B-2 postcondition failed: expected 25 public stores.';\n"
        "  end if;\n\n"
        "  select count(*) into matched_count\n"
        "    from (values\n"
        f"        {expected_values}\n"
        "    ) as expected(\n"
        "      id, name, address, latitude, longitude, burger_style,\n"
        "      source_type, source_as_of, verified_at\n"
        "    )\n"
        "    join public.stores as store on store.id = expected.id\n"
        "   where store.name = expected.name\n"
        "     and store.address = expected.address\n"
        "     and store.latitude = expected.latitude\n"
        "     and store.longitude = expected.longitude\n"
        "     and store.burger_style = expected.burger_style\n"
        "     and store.verification_status = 'verified'\n"
        "     and store.is_active = true\n"
        "     and store.source_type = expected.source_type\n"
        "     and store.source_as_of = expected.source_as_of\n"
        "     and store.verified_at = expected.verified_at;\n"
        f"  if matched_count <> {EXPECTED_APPROVALS} then\n"
        "    raise exception 'Phase 6B-2 postcondition failed: inserted values differ.';\n"
        "  end if;\n"
        "end\n"
        "$phase_6b2$;\n\n"
        "commit;\n"
    )
    for label, pattern in FORBIDDEN_SQL_PATTERNS.items():
        if pattern.search(sql):
            raise StorePublishingError(f"생성 SQL에 금지 내용이 포함됐습니다: {label}")
    return sql


def generate_phase_6b2_store_sql(
    review_path: Path,
    approval_path: Path,
    migration_path: Path,
    output_path: Path,
    *,
    today=None,
) -> int:
    import datetime as dt

    approval_today = today or dt.datetime.now(dt.timezone.utc).date()
    approvals, _ = load_phase_6b2_approval_manifest(
        approval_path, today=approval_today
    )
    review_headers, review_rows = read_csv_rows(review_path, set(REVIEW_HEADERS))
    if review_headers != list(REVIEW_HEADERS):
        raise StorePublishingError("게시 검수표 컬럼 또는 순서가 다릅니다.")
    schema = parse_store_schema(migration_path)
    eligible = _validate_review_rows(
        review_rows, schema.source_types, schema.verification_statuses
    )
    if len(eligible) != EXPECTED_FINAL_PUBLIC:
        raise StorePublishingError("게시 검수표가 verified+active 25곳 상태가 아닙니다.")
    eligible_by_id = {str(row["id"]): row for row in eligible}
    review_by_candidate = {row["candidateId"].strip(): row for row in review_rows}
    if len(review_by_candidate) != len(review_rows):
        raise StorePublishingError("게시 검수표 candidateId가 중복됐습니다.")

    selected: list[Mapping[str, object]] = []
    for approval in approvals:
        review_row = review_by_candidate.get(approval["candidateId"])
        if review_row is None:
            raise StorePublishingError("승인 매장을 게시 검수표에서 찾을 수 없습니다.")
        if review_row["storeId"].strip() != approval["storeId"]:
            raise StorePublishingError("승인 storeId가 게시 검수표와 다릅니다.")
        if not _same_review_identity(review_row, approval):
            raise StorePublishingError("승인 매장명 또는 주소가 게시 검수표와 다릅니다.")
        selected_row = eligible_by_id.get(approval["storeId"])
        if selected_row is None:
            raise StorePublishingError("승인 매장이 verified+active 상태가 아닙니다.")
        if selected_row["burger_style"] != approval["approvedStyle"]:
            raise StorePublishingError("승인 스타일이 게시 검수표와 다릅니다.")
        if selected_row["source_as_of"].isoformat() != approval["sourceAsOf"]:
            raise StorePublishingError("sourceAsOf가 승인 근거와 다릅니다.")
        selected.append(selected_row)

    selected_ids = {str(row["id"]) for row in selected}
    if len(selected_ids) != EXPECTED_APPROVALS:
        raise StorePublishingError("Phase 6B-2 신규 UUID가 정확히 2개가 아닙니다.")
    if len(set(eligible_by_id) - selected_ids) != EXPECTED_INITIAL_PUBLIC:
        raise StorePublishingError("기존 공개 23곳과 신규 2곳을 분리할 수 없습니다.")

    sql = build_guarded_phase_6b2_sql(selected)
    if output_path.exists():
        if output_path.read_text(encoding="utf-8") != sql:
            raise StorePublishingError(
                "기존 Phase 6B-2 SQL이 현재 승인 입력과 달라 덮어쓰지 않습니다."
            )
        return len(selected)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_name(f".{output_path.name}.tmp")
    try:
        temporary_path.write_text(sql, encoding="utf-8")
        temporary_path.replace(output_path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise StorePublishingError(f"Phase 6B-2 SQL을 저장할 수 없습니다: {output_path}") from error
    return len(selected)


def _same_review_identity(
    row: Mapping[str, str], approval: Mapping[str, object]
) -> bool:
    return normalize_store_text(row["name"]) == normalize_store_text(
        str(approval["name"])
    ) and normalize_store_text(row["address"]) == normalize_store_text(
        str(approval["address"])
    )


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--approvals", type=Path, default=DEFAULT_APPROVAL_PATH)
    parser.add_argument("--migration", type=Path, default=DEFAULT_MIGRATION_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        count = generate_phase_6b2_store_sql(
            args.review,
            args.approvals,
            args.migration,
            args.output,
        )
        print(
            json.dumps(
                {
                    "generatedRows": count,
                    "sha256": file_sha256(args.output),
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
