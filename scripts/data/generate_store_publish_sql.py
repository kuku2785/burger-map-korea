#!/usr/bin/env python3
"""Generate offline, manually-applied SQL for reviewed public stores."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import re
import sys
import uuid
from pathlib import Path
from typing import Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from store_publishing_common import (  # noqa: E402
    ALLOWED_REVIEW_DECISIONS,
    REVIEW_HEADERS,
    STORE_INSERT_COLUMNS,
    StorePublishingError,
    normalize_store_text,
    parse_coordinate,
    parse_store_schema,
    read_csv_rows,
)
from build_burger_style_review import (  # noqa: E402
    ALLOWED_STYLES,
    read_validated_style_review_rows,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_REVIEW_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_store_publish_review.csv"
)
DEFAULT_MIGRATION_PATH = (
    PROJECT_ROOT / "supabase" / "migrations" / "0001_init_store_schema.sql"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_store_publish.sql"
)
FORBIDDEN_SQL_PATTERNS = {
    "candidateId": re.compile(r"candidateId", re.IGNORECASE),
    "external Place ID column": re.compile(
        r"(?:source_place_id|place_url|kakao_place_id|google_place_id)",
        re.IGNORECASE,
    ),
    "Supabase key": re.compile(
        r"(?:sb_(?:publishable|secret)_[A-Za-z0-9_-]{20,}|"
        r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)"
    ),
    "service URL": re.compile(r"https?://", re.IGNORECASE),
}


class NoApprovedStoresError(StorePublishingError):
    """Raised when a review has no verified and active rows to publish."""


def _parse_boolean(value: str, candidate_id: str) -> bool:
    normalized = value.strip().lower()
    if normalized not in {"true", "false"}:
        raise StorePublishingError(
            f"isActive는 true 또는 false여야 합니다: {candidate_id}"
        )
    return normalized == "true"


def _parse_source_date(value: str, candidate_id: str) -> dt.date:
    try:
        return dt.date.fromisoformat(value.strip())
    except ValueError:
        raise StorePublishingError(
            f"sourceAsOf는 YYYY-MM-DD 형식이어야 합니다: {candidate_id}"
        ) from None


def _parse_verified_at(value: str, candidate_id: str) -> dt.datetime:
    normalized = value.strip().replace("Z", "+00:00")
    try:
        verified_at = dt.datetime.fromisoformat(normalized)
    except ValueError:
        raise StorePublishingError(
            f"verifiedAt은 ISO 8601 형식이어야 합니다: {candidate_id}"
        ) from None
    if verified_at.tzinfo is None or verified_at.utcoffset() is None:
        raise StorePublishingError(
            f"verifiedAt에는 시간대가 포함되어야 합니다: {candidate_id}"
        )
    return verified_at


def _validate_review_rows(
    rows: Sequence[Mapping[str, str]],
    allowed_source_types: set[str] | frozenset[str],
    allowed_db_statuses: set[str] | frozenset[str],
) -> list[dict[str, object]]:
    if "verified" not in allowed_db_statuses:
        raise StorePublishingError("migration이 verified 상태를 허용하지 않습니다.")
    eligible: list[dict[str, object]] = []
    seen_store_ids: set[str] = set()
    seen_candidate_ids: set[str] = set()
    seen_identity: dict[tuple[str, str], str] = {}
    seen_name_coordinates: list[tuple[str, float, float, str]] = []

    for row in rows:
        candidate_id = row.get("candidateId", "").strip()
        if not candidate_id or candidate_id in seen_candidate_ids:
            raise StorePublishingError(
                f"candidateId가 비었거나 중복됐습니다: {candidate_id}"
            )
        seen_candidate_ids.add(candidate_id)
        try:
            store_id = str(uuid.UUID(row.get("storeId", "").strip()))
        except ValueError:
            raise StorePublishingError(f"storeId가 UUID가 아닙니다: {candidate_id}") from None
        if store_id in seen_store_ids:
            raise StorePublishingError(f"storeId가 중복됐습니다: {candidate_id}")
        seen_store_ids.add(store_id)

        name = row.get("name", "").strip()
        address = row.get("address", "").strip()
        if not name or not address:
            raise StorePublishingError(f"이름 또는 주소가 비었습니다: {candidate_id}")
        latitude = parse_coordinate(row.get("latitude", ""), "latitude", candidate_id)
        longitude = parse_coordinate(
            row.get("longitude", ""), "longitude", candidate_id
        )
        if latitude == 0 and longitude == 0:
            raise StorePublishingError(f"0,0 좌표는 게시할 수 없습니다: {candidate_id}")

        identity = (normalize_store_text(name), normalize_store_text(address))
        if identity in seen_identity:
            raise StorePublishingError(
                f"중복 매장 의심: {seen_identity[identity]}, {candidate_id}"
            )
        seen_identity[identity] = candidate_id
        for previous_name, previous_latitude, previous_longitude, previous_id in (
            seen_name_coordinates
        ):
            if identity[0] == previous_name and _distance_meters(
                latitude,
                longitude,
                previous_latitude,
                previous_longitude,
            ) <= 100:
                raise StorePublishingError(
                    f"인접한 동일 이름 중복 의심: {previous_id}, {candidate_id}"
                )
        seen_name_coordinates.append((identity[0], latitude, longitude, candidate_id))

        decision = row.get("publishDecision", "").strip()
        if decision not in ALLOWED_REVIEW_DECISIONS:
            raise StorePublishingError(
                f"허용되지 않은 publishDecision입니다: {candidate_id}, {decision}"
            )
        is_active = _parse_boolean(row.get("isActive", ""), candidate_id)
        source_type = row.get("sourceType", "").strip()
        if source_type not in allowed_source_types:
            raise StorePublishingError(
                f"migration에서 허용하지 않는 sourceType입니다: {candidate_id}"
            )

        if decision != "verified":
            if is_active:
                raise StorePublishingError(
                    f"verified가 아닌 행은 활성화할 수 없습니다: {candidate_id}"
                )
            if row.get("verifiedAt", "").strip():
                raise StorePublishingError(
                    f"verified가 아닌 행에는 verifiedAt을 둘 수 없습니다: {candidate_id}"
                )
            continue

        source_as_of = _parse_source_date(
            row.get("sourceAsOf", ""),
            candidate_id,
        )
        verified_at = _parse_verified_at(
            row.get("verifiedAt", ""),
            candidate_id,
        )
        verification_note = row.get("verificationNote", "").strip()
        if not verification_note:
            raise StorePublishingError(
                f"verified 행에 verificationNote가 필요합니다: {candidate_id}"
            )
        if not is_active:
            continue
        burger_style = row.get("burgerStyle", "").strip()
        eligible.append(
            {
                "id": store_id,
                "name": name,
                "address": address,
                "latitude": latitude,
                "longitude": longitude,
                "burger_style": burger_style or None,
                "verification_status": "verified",
                "is_active": True,
                "source_type": source_type,
                "source_as_of": source_as_of,
                "verified_at": verified_at,
            }
        )
    return eligible


def _apply_style_review(
    rows: Sequence[Mapping[str, str]],
    style_review_rows: Sequence[Mapping[str, str]],
) -> list[dict[str, str]]:
    style_by_candidate: dict[str, Mapping[str, str]] = {}
    for style_row in style_review_rows:
        candidate_id = style_row.get("candidateId", "").strip()
        if not candidate_id or candidate_id in style_by_candidate:
            raise StorePublishingError(
                f"스타일 검수표 candidateId가 비었거나 중복됐습니다: {candidate_id}"
            )
        style_by_candidate[candidate_id] = style_row

    review_ids = {row.get("candidateId", "").strip() for row in rows}
    if review_ids != set(style_by_candidate):
        raise StorePublishingError("게시 검수표와 스타일 검수표 candidateId 집합이 다릅니다.")

    output: list[dict[str, str]] = []
    for raw_row in rows:
        row = dict(raw_row)
        candidate_id = row.get("candidateId", "").strip()
        style_row = style_by_candidate[candidate_id]
        try:
            style_store_id = str(uuid.UUID(style_row.get("storeId", "").strip()))
            publish_store_id = str(uuid.UUID(row.get("storeId", "").strip()))
        except ValueError:
            raise StorePublishingError(
                f"style-review 연결 storeId가 UUID가 아닙니다: {candidate_id}"
            ) from None
        mismatched = (["storeId"] if style_store_id != publish_store_id else []) + [
            field
            for field in ("name", "address")
            if normalize_store_text(style_row.get(field, ""))
            != normalize_store_text(row.get(field, ""))
        ]
        if mismatched:
            raise StorePublishingError(
                f"게시 검수표와 스타일 검수표가 다릅니다: "
                f"{candidate_id}, {mismatched}"
            )
        if style_row.get("reviewStatus", "").strip() == "approved":
            style = style_row.get("proposedBurgerStyle", "").strip()
            if style not in ALLOWED_STYLES or style == "unclassified":
                raise StorePublishingError(
                    f"승인 스타일이 올바르지 않습니다: {candidate_id}, {style}"
                )
            row["burgerStyle"] = style
        else:
            row["burgerStyle"] = "unclassified"
        output.append(row)
    return output


def _distance_meters(
    latitude_a: float,
    longitude_a: float,
    latitude_b: float,
    longitude_b: float,
) -> float:
    radius_meters = 6_371_000
    lat_a = math.radians(latitude_a)
    lat_b = math.radians(latitude_b)
    delta_lat = lat_b - lat_a
    delta_lon = math.radians(longitude_b - longitude_a)
    haversine = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat_a) * math.cos(lat_b) * math.sin(delta_lon / 2) ** 2
    )
    return 2 * radius_meters * math.asin(math.sqrt(haversine))


def _sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _sql_value(column: str, value: object) -> str:
    if value is None:
        return "NULL"
    if column == "id":
        return f"{_sql_text(str(value))}::uuid"
    if column in {"latitude", "longitude"}:
        return repr(float(value))
    if column == "is_active":
        return "true" if value is True else "false"
    if column == "source_as_of":
        return f"DATE {_sql_text(value.isoformat())}"
    if column == "verified_at":
        return f"TIMESTAMPTZ {_sql_text(value.isoformat())}"
    return _sql_text(str(value))


def build_insert_sql(rows: Sequence[Mapping[str, object]]) -> str:
    if not rows:
        raise NoApprovedStoresError(
            "verified이면서 active인 매장이 0개라 게시 SQL을 생성하지 않습니다."
        )
    column_sql = ",\n  ".join(STORE_INSERT_COLUMNS)
    value_groups = []
    for row in rows:
        values = ",\n    ".join(
            _sql_value(column, row[column]) for column in STORE_INSERT_COLUMNS
        )
        value_groups.append(f"  (\n    {values}\n  )")
    sql = (
        "begin;\n\n"
        "insert into public.stores (\n"
        f"  {column_sql}\n"
        ") values\n"
        + ",\n".join(value_groups)
        + ";\n\ncommit;\n"
    )
    for label, pattern in FORBIDDEN_SQL_PATTERNS.items():
        if pattern.search(sql):
            raise StorePublishingError(f"생성 SQL에 금지 값이 포함됐습니다: {label}")
    return sql


def generate_publish_sql(
    review_path: Path,
    migration_path: Path,
    output_path: Path,
    style_review_path: Path | None = None,
) -> int:
    if output_path.exists():
        raise StorePublishingError(f"출력 SQL이 이미 존재합니다: {output_path}")
    headers, rows = read_csv_rows(review_path, set(REVIEW_HEADERS))
    if headers != list(REVIEW_HEADERS):
        raise StorePublishingError("게시 검수표 컬럼 또는 순서가 다릅니다.")
    if style_review_path is not None:
        style_review_rows = read_validated_style_review_rows(style_review_path)
        rows = _apply_style_review(rows, style_review_rows)
    schema = parse_store_schema(migration_path)
    eligible = _validate_review_rows(
        rows,
        schema.source_types,
        schema.verification_statuses,
    )
    sql = build_insert_sql(eligible)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        output_path.write_text(sql, encoding="utf-8")
    except OSError as error:
        raise StorePublishingError(f"게시 SQL을 저장할 수 없습니다: {output_path}") from error
    return len(eligible)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="사람 검수가 끝난 verified+active 매장의 SQL을 생성합니다."
    )
    parser.add_argument("--review", type=Path, default=DEFAULT_REVIEW_PATH)
    parser.add_argument("--migration", type=Path, default=DEFAULT_MIGRATION_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--style-review", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        generated_rows = generate_publish_sql(
            args.review,
            args.migration,
            args.output,
            args.style_review,
        )
        print(
            json.dumps(
                {
                    "generatedRows": generated_rows,
                    "outputPath": str(args.output.resolve()),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except NoApprovedStoresError as error:
        print(f"안전 중단: {error}")
        return 3
    except StorePublishingError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
