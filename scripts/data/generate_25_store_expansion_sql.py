#!/usr/bin/env python3
"""Generate guarded INSERT SQL for the 13 Phase 6B approvals.

If the output already exists, the generator accepts identical content. It refuses
different content without overwriting the existing SQL file.
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

from apply_25_store_expansion_approvals import (  # noqa: E402
    DEFAULT_APPROVAL_PATH,
    DEFAULT_EXPANSION_PATH,
    DEFAULT_PUBLISH_PATH,
    DEFAULT_STYLE_PATH,
    EXPECTED_APPROVALS,
    EXPECTED_FINAL_PUBLIC,
    EXPECTED_INITIAL_PUBLIC,
    load_approval_manifest,
)
from build_25_store_expansion_review import OUTPUT_HEADERS  # noqa: E402
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
    / "yongsan_burger_store_publish_25_expansion.sql"
)
EXPECTED_STYLE_COUNTS = {
    "classic": 14,
    "other": 3,
    "chicken": 2,
    "smash": 1,
    "unclassified": 3,
}
FORBIDDEN_SQL_PATTERNS = {
    "internal identifier": re.compile(
        r"(?:candidateId|reviewItemId|sourcePlaceId|discoveryId|p6b_)", re.IGNORECASE
    ),
    "external place data": re.compile(
        r"(?:source_place_id|place_url|kakao_place_id|google_place_id|https?://)",
        re.IGNORECASE,
    ),
    "review evidence": re.compile(
        r"(?:verificationNote|evidenceUrl|recommendationReason|remainingRisk)",
        re.IGNORECASE,
    ),
    "credential": re.compile(
        r"(?:AIza[0-9A-Za-z_-]{30,}|sb_(?:publishable|secret)_[0-9A-Za-z_-]{20,}|"
        r"eyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+|"
        r"https://[a-z0-9]{15,}\.supabase\.co)",
        re.IGNORECASE,
    ),
    "write operation other than INSERT": re.compile(
        r"\b(?:update|delete|upsert|rpc)\b|on\s+conflict", re.IGNORECASE
    ),
}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


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


def build_guarded_25_store_sql(rows: Sequence[Mapping[str, object]]) -> str:
    if len(rows) != EXPECTED_APPROVALS:
        raise StorePublishingError(
            f"신규 INSERT 대상은 정확히 {EXPECTED_APPROVALS}곳이어야 합니다."
        )
    ids = [str(row["id"]) for row in rows]
    if len(ids) != len(set(ids)):
        raise StorePublishingError("신규 INSERT UUID가 중복됐습니다.")

    id_list = ",\n      ".join(f"{_sql_text(store_id)}::uuid" for store_id in ids)
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
        "do $phase_6b_approval$\n"
        "declare\n"
        "  total_count integer;\n"
        "  public_count integer;\n"
        "  existing_new_count integer;\n"
        "  inserted_count integer;\n"
        "  matched_count integer;\n"
        "  matched_style_count integer;\n"
        "begin\n"
        "  select count(*) into total_count from public.stores;\n"
        f"  if total_count <> {EXPECTED_INITIAL_PUBLIC} then\n"
        "    raise exception 'Phase 6B precondition failed: expected 10 total stores.';\n"
        "  end if;\n\n"
        "  select count(*) into public_count\n"
        "    from public.stores\n"
        "   where verification_status = 'verified' and is_active = true;\n"
        f"  if public_count <> {EXPECTED_INITIAL_PUBLIC} then\n"
        "    raise exception 'Phase 6B precondition failed: expected 10 public stores.';\n"
        "  end if;\n\n"
        "  select count(*) into existing_new_count\n"
        "    from public.stores\n"
        "   where id in (\n"
        f"      {id_list}\n"
        "   );\n"
        "  if existing_new_count <> 0 then\n"
        "    raise exception 'Phase 6B precondition failed: a new UUID already exists.';\n"
        "  end if;\n\n"
        "  insert into public.stores (\n"
        f"      {columns}\n"
        "  ) values\n"
        + ",\n".join(values)
        + ";\n\n"
        "  get diagnostics inserted_count = row_count;\n"
        f"  if inserted_count <> {EXPECTED_APPROVALS} then\n"
        "    raise exception 'Phase 6B insert count check failed.';\n"
        "  end if;\n\n"
        "  select count(*) into total_count from public.stores;\n"
        f"  if total_count <> {EXPECTED_FINAL_PUBLIC} then\n"
        "    raise exception 'Phase 6B postcondition failed: expected 23 total stores.';\n"
        "  end if;\n\n"
        "  select count(*) into public_count\n"
        "    from public.stores\n"
        "   where verification_status = 'verified' and is_active = true;\n"
        f"  if public_count <> {EXPECTED_FINAL_PUBLIC} then\n"
        "    raise exception 'Phase 6B postcondition failed: expected 23 public stores.';\n"
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
        "    raise exception 'Phase 6B postcondition failed: inserted values differ.';\n"
        "  end if;\n\n"
        "  select count(*) into matched_style_count\n"
        "    from (values\n"
        "      ('classic'::text, 14::bigint),\n"
        "      ('other'::text, 3::bigint),\n"
        "      ('chicken'::text, 2::bigint),\n"
        "      ('smash'::text, 1::bigint),\n"
        "      ('unclassified'::text, 3::bigint)\n"
        "    ) as expected_style(burger_style, store_count)\n"
        "    join (\n"
        "      select burger_style, count(*) as store_count\n"
        "        from public.stores\n"
        "       where verification_status = 'verified' and is_active = true\n"
        "       group by burger_style\n"
        "    ) as actual_style using (burger_style)\n"
        "   where actual_style.store_count = expected_style.store_count;\n"
        "  if matched_style_count <> 5 then\n"
        "    raise exception 'Phase 6B postcondition failed: style distribution differs.';\n"
        "  end if;\n"
        "end\n"
        "$phase_6b_approval$;\n\n"
        "commit;\n"
    )
    for label, pattern in FORBIDDEN_SQL_PATTERNS.items():
        if pattern.search(sql):
            raise StorePublishingError(f"생성 SQL에 금지 내용이 포함됐습니다: {label}")
    return sql


def generate_25_store_expansion_sql(
    review_path: Path,
    expansion_path: Path,
    style_path: Path,
    approval_path: Path,
    migration_path: Path,
    output_path: Path,
) -> int:
    review_headers, review_rows = read_csv_rows(review_path, set(REVIEW_HEADERS))
    expansion_headers, expansion_rows = read_csv_rows(
        expansion_path, set(OUTPUT_HEADERS)
    )
    _, style_rows = read_csv_rows(
        style_path,
        {
            "storeId",
            "candidateId",
            "proposedBurgerStyle",
            "reviewStatus",
        },
    )
    if review_headers != list(REVIEW_HEADERS):
        raise StorePublishingError("게시 검수표 컬럼 또는 순서가 다릅니다.")
    if expansion_headers != list(OUTPUT_HEADERS):
        raise StorePublishingError("Phase 6B 검수표 컬럼 또는 순서가 다릅니다.")
    approvals = load_approval_manifest(approval_path)
    expansion_by_id = {
        row["reviewItemId"].strip(): row for row in expansion_rows
    }
    if len(expansion_by_id) != len(expansion_rows):
        raise StorePublishingError("Phase 6B reviewItemId가 중복됐습니다.")

    schema = parse_store_schema(migration_path)
    eligible = _validate_review_rows(
        review_rows, schema.source_types, schema.verification_statuses
    )
    if len(eligible) != EXPECTED_FINAL_PUBLIC:
        raise StorePublishingError("게시 검수표가 verified+active 23곳 상태가 아닙니다.")
    eligible_by_id = {str(row["id"]): row for row in eligible}
    review_by_candidate = {row["candidateId"].strip(): row for row in review_rows}
    if len(review_by_candidate) != len(review_rows):
        raise StorePublishingError("게시 검수표 candidateId가 중복됐습니다.")

    selected: list[Mapping[str, object]] = []
    selected_ids: set[str] = set()
    for approval in approvals:
        review_row = review_by_candidate.get(approval["candidateId"])
        phase_row = expansion_by_id.get(approval["reviewItemId"])
        if review_row is None or phase_row is None:
            raise StorePublishingError(
                f"승인 매장을 게시 입력에서 찾을 수 없습니다: {approval['reviewItemId']}"
            )
        store_id = review_row["storeId"].strip()
        if approval["sourceGroup"] == "pending" and store_id != approval["storeId"]:
            raise StorePublishingError(f"승인 storeId가 다릅니다: {approval['reviewItemId']}")
        if not normalize_store_text(review_row["name"]) == normalize_store_text(
            approval["name"]
        ):
            raise StorePublishingError(f"승인 매장명이 다릅니다: {approval['reviewItemId']}")
        if not normalize_store_text(review_row["address"]) == normalize_store_text(
            approval["address"]
        ):
            raise StorePublishingError(f"승인 주소가 다릅니다: {approval['reviewItemId']}")
        row = eligible_by_id.get(store_id)
        if row is None:
            raise StorePublishingError(
                f"승인 매장이 verified+active 대상이 아닙니다: {approval['reviewItemId']}"
            )
        if row["burger_style"] != approval["approvedStyle"]:
            raise StorePublishingError(f"승인 스타일이 다릅니다: {approval['reviewItemId']}")
        if row["source_as_of"].isoformat() != phase_row["latestEvidenceAsOf"].strip():
            raise StorePublishingError(f"sourceAsOf가 근거 기준일과 다릅니다: {approval['reviewItemId']}")
        if store_id in selected_ids:
            raise StorePublishingError("신규 SQL 대상 UUID가 중복됐습니다.")
        selected_ids.add(store_id)
        selected.append(row)

    if len(selected) != EXPECTED_APPROVALS:
        raise StorePublishingError("신규 SQL 대상이 정확히 13곳이 아닙니다.")
    existing_ids = set(eligible_by_id) - selected_ids
    if len(existing_ids) != EXPECTED_INITIAL_PUBLIC:
        raise StorePublishingError("기존 공개 10곳과 신규 승인 13곳을 분리할 수 없습니다.")

    style_by_candidate = {
        row["candidateId"].strip(): row for row in style_rows
    }
    if len(style_by_candidate) != len(style_rows):
        raise StorePublishingError("스타일 검수표 candidateId가 중복됐습니다.")
    style_counts: dict[str, int] = {}
    for row in eligible:
        review_row = next(
            item for item in review_rows if item["storeId"].strip() == str(row["id"])
        )
        style = row["burger_style"]
        if style is None:
            style_row = style_by_candidate.get(review_row["candidateId"].strip())
            if (
                style_row is None
                or style_row["storeId"].strip() != str(row["id"])
                or style_row["reviewStatus"].strip() != "approved"
                or not style_row["proposedBurgerStyle"].strip()
            ):
                raise StorePublishingError(
                    "공란 게시 스타일을 승인된 스타일 검수표로 해석할 수 없습니다."
                )
            style = style_row["proposedBurgerStyle"].strip()
        style = str(style)
        style_counts[style] = style_counts.get(style, 0) + 1
    if style_counts != EXPECTED_STYLE_COUNTS:
        raise StorePublishingError(f"예상 최종 스타일 분포와 다릅니다: {style_counts}")

    sql = build_guarded_25_store_sql(selected)
    if output_path.exists():
        if output_path.read_text(encoding="utf-8") != sql:
            raise StorePublishingError("기존 Phase 6B SQL이 현재 승인 입력과 다릅니다.")
        return len(selected)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_name(f".{output_path.name}.tmp")
    try:
        temporary_path.write_text(sql, encoding="utf-8")
        temporary_path.replace(output_path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise StorePublishingError(f"Phase 6B SQL을 저장할 수 없습니다: {output_path}") from error
    return len(selected)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--expansion-review", type=Path, default=DEFAULT_EXPANSION_PATH)
    parser.add_argument("--style-review", type=Path, default=DEFAULT_STYLE_PATH)
    parser.add_argument("--approvals", type=Path, default=DEFAULT_APPROVAL_PATH)
    parser.add_argument("--migration", type=Path, default=DEFAULT_MIGRATION_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        count = generate_25_store_expansion_sql(
            args.review,
            args.expansion_review,
            args.style_review,
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
