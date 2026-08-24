#!/usr/bin/env python3
"""Generate guarded one-time INSERT SQL for the approved Phase 6A expansion."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from apply_publish_expansion_approvals import (  # noqa: E402
    DEFAULT_APPROVAL_PATH,
    DEFAULT_PUBLISH_REVIEW_PATH,
    EXPECTED_APPROVALS,
    EXPECTED_FINAL_VERIFIED,
    load_approval_manifest,
)
from generate_store_publish_sql import _sql_value, _validate_review_rows  # noqa: E402
from store_publishing_common import (  # noqa: E402
    REVIEW_HEADERS,
    STORE_INSERT_COLUMNS,
    StorePublishingError,
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
    / "yongsan_burger_store_publish_expansion.sql"
)
FORBIDDEN_SQL_PATTERNS = {
    "candidateId": re.compile(r"candidateId", re.IGNORECASE),
    "external place data": re.compile(
        r"(?:source_place_id|place_url|kakao_place_id|google_place_id|https?://)",
        re.IGNORECASE,
    ),
    "review evidence": re.compile(
        r"(?:verificationNote|evidenceUrl|sourceAsOfBasis)", re.IGNORECASE
    ),
    "credential": re.compile(
        r"(?:AIza[0-9A-Za-z_-]{30,}|sb_(?:publishable|secret)_[0-9A-Za-z_-]{20,}|"
        r"eyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+)"
    ),
    "write operation other than INSERT": re.compile(
        r"\b(?:update|delete|upsert|rpc)\b|on\s+conflict", re.IGNORECASE
    ),
}


def _sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def build_guarded_expansion_sql(rows: Sequence[Mapping[str, object]]) -> str:
    if len(rows) != EXPECTED_APPROVALS:
        raise StorePublishingError(f"신규 INSERT 대상은 정확히 {EXPECTED_APPROVALS}곳이어야 합니다.")
    ids = [str(row["id"]) for row in rows]
    if len(set(ids)) != EXPECTED_APPROVALS:
        raise StorePublishingError("신규 INSERT UUID가 중복됐습니다.")

    id_list = ",\n      ".join(f"{_sql_text(store_id)}::uuid" for store_id in ids)
    expected_values = ",\n        ".join(
        f"({_sql_text(str(row['id']))}::uuid, {_sql_text(str(row['burger_style']))})"
        for row in rows
    )
    columns = ",\n      ".join(STORE_INSERT_COLUMNS)
    value_groups = []
    for row in rows:
        values = ",\n        ".join(
            _sql_value(column, row[column]) for column in STORE_INSERT_COLUMNS
        )
        value_groups.append(f"      (\n        {values}\n      )")

    sql = (
        "begin;\n\n"
        "do $phase_6a_2$\n"
        "declare\n"
        "  existing_count integer;\n"
        "  inserted_count integer;\n"
        "  valid_count integer;\n"
        "begin\n"
        "  select count(*)\n"
        "    into existing_count\n"
        "    from public.stores\n"
        "   where id in (\n"
        f"      {id_list}\n"
        "   );\n\n"
        "  if existing_count <> 0 then\n"
        "    raise exception 'Phase 6A-2 precondition failed: an expansion UUID already exists.';\n"
        "  end if;\n\n"
        "  insert into public.stores (\n"
        f"      {columns}\n"
        "  ) values\n"
        + ",\n".join(value_groups)
        + ";\n\n"
        "  get diagnostics inserted_count = row_count;\n"
        f"  if inserted_count <> {EXPECTED_APPROVALS} then\n"
        "    raise exception 'Phase 6A-2 insert count check failed.';\n"
        "  end if;\n\n"
        "  select count(*)\n"
        "    into valid_count\n"
        "    from (values\n"
        f"        {expected_values}\n"
        "    ) as expected(id, burger_style)\n"
        "    join public.stores as store on store.id = expected.id\n"
        "   where store.verification_status = 'verified'\n"
        "     and store.is_active = true\n"
        "     and store.burger_style = expected.burger_style;\n\n"
        f"  if valid_count <> {EXPECTED_APPROVALS} then\n"
        "    raise exception 'Phase 6A-2 postcondition failed.';\n"
        "  end if;\n"
        "end\n"
        "$phase_6a_2$;\n\n"
        "commit;\n"
    )
    for label, pattern in FORBIDDEN_SQL_PATTERNS.items():
        if pattern.search(sql):
            raise StorePublishingError(f"생성 SQL에 금지 내용이 포함됐습니다: {label}")
    return sql


def generate_publish_expansion_sql(
    review_path: Path,
    approval_path: Path,
    migration_path: Path,
    output_path: Path,
) -> int:
    if output_path.exists():
        raise StorePublishingError(f"출력 SQL이 이미 존재합니다: {output_path}")
    headers, review_rows = read_csv_rows(review_path, set(REVIEW_HEADERS))
    if headers != list(REVIEW_HEADERS):
        raise StorePublishingError("게시 검수표 컬럼 또는 순서가 다릅니다.")
    manifest = load_approval_manifest(approval_path)
    schema = parse_store_schema(migration_path)
    eligible = _validate_review_rows(
        review_rows, schema.source_types, schema.verification_statuses
    )
    if len(eligible) != EXPECTED_FINAL_VERIFIED:
        raise StorePublishingError(
            "게시 검수표의 verified+active 매장이 기존 1곳과 신규 9곳이 아닙니다."
        )
    eligible_by_id = {str(row["id"]): row for row in eligible}
    approval_ids = [row["storeId"] for row in manifest["approvals"]]
    selected: list[Mapping[str, object]] = []
    for approval in manifest["approvals"]:
        row = eligible_by_id.get(approval["storeId"])
        if row is None:
            raise StorePublishingError(
                f"승인 매장이 verified+active 게시 대상이 아닙니다: {approval['name']}"
            )
        if row["burger_style"] != approval["approvedStyle"]:
            raise StorePublishingError(f"게시 스타일이 승인 명세와 다릅니다: {approval['name']}")
        if row["source_as_of"].isoformat() != approval["sourceAsOf"]:
            raise StorePublishingError(f"sourceAsOf가 승인 명세와 다릅니다: {approval['name']}")
        selected.append(row)
    if len(approval_ids) != len(set(approval_ids)) or len(selected) != EXPECTED_APPROVALS:
        raise StorePublishingError("승인 SQL 대상 UUID 집합이 올바르지 않습니다.")
    if set(str(row["id"]) for row in selected) != set(approval_ids):
        raise StorePublishingError("승인 SQL 대상이 allowlist와 다릅니다.")

    sql = build_guarded_expansion_sql(selected)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_name(f".{output_path.name}.tmp")
    try:
        temporary_path.write_text(sql, encoding="utf-8")
        temporary_path.replace(output_path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise StorePublishingError(f"확장 게시 SQL을 저장할 수 없습니다: {output_path}") from error
    return len(selected)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Phase 6A 승인 9곳의 일회성 게시 SQL을 생성합니다.")
    parser.add_argument("--review", type=Path, default=DEFAULT_PUBLISH_REVIEW_PATH)
    parser.add_argument("--approvals", type=Path, default=DEFAULT_APPROVAL_PATH)
    parser.add_argument("--migration", type=Path, default=DEFAULT_MIGRATION_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        count = generate_publish_expansion_sql(
            args.review, args.approvals, args.migration, args.output
        )
        print(
            json.dumps(
                {"generatedRows": count, "outputPath": str(args.output.resolve())},
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
