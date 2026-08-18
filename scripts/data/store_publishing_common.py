#!/usr/bin/env python3
"""Shared validation helpers for the offline store publishing pipeline."""

from __future__ import annotations

import csv
import math
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


STORE_INSERT_COLUMNS = (
    "id",
    "name",
    "address",
    "latitude",
    "longitude",
    "burger_style",
    "verification_status",
    "is_active",
    "source_type",
    "source_as_of",
    "verified_at",
)
REVIEW_HEADERS = (
    "storeId",
    "candidateId",
    "name",
    "address",
    "latitude",
    "longitude",
    "burgerStyle",
    "sourceType",
    "sourceAsOf",
    "publishDecision",
    "isActive",
    "verifiedAt",
    "verificationNote",
)
ALLOWED_REVIEW_DECISIONS = {
    "pending",
    "needs_recheck",
    "verified",
    "rejected",
    "hold",
}


class StorePublishingError(ValueError):
    """Raised when local publishing data violates a safety rule."""


@dataclass(frozen=True)
class StoreSchema:
    columns: frozenset[str]
    source_types: frozenset[str]
    verification_statuses: frozenset[str]


def read_csv_rows(
    path: Path,
    required_headers: set[str],
) -> tuple[list[str], list[dict[str, str]]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            reader = csv.DictReader(input_file)
            headers = list(reader.fieldnames or [])
            rows = list(reader)
    except OSError as error:
        raise StorePublishingError(f"CSV를 열 수 없습니다: {path}") from error
    missing = sorted(required_headers - set(headers))
    if missing:
        raise StorePublishingError(f"CSV 필수 컬럼이 없습니다: {path}, {missing}")
    return headers, rows


def write_csv_rows(
    path: Path,
    headers: Sequence[str],
    rows: Sequence[Mapping[str, str]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_name(f".{path.name}.tmp")
    try:
        with temporary_path.open("w", encoding="utf-8-sig", newline="") as output_file:
            writer = csv.DictWriter(output_file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)
        temporary_path.replace(path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise StorePublishingError(f"CSV를 저장할 수 없습니다: {path}") from error


def parse_store_schema(path: Path) -> StoreSchema:
    try:
        sql = path.read_text(encoding="utf-8")
    except OSError as error:
        raise StorePublishingError(f"migration을 열 수 없습니다: {path}") from error

    table_match = re.search(
        r"create\s+table\s+public\.stores\s*\((.*?)\n\);",
        sql,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if table_match is None:
        raise StorePublishingError("public.stores 정의를 migration에서 찾지 못했습니다.")
    columns = frozenset(
        match.group(1).lower()
        for match in re.finditer(
            r"^\s{2}([a-z_][a-z0-9_]*)\s+"
            r"(?:uuid|text|double\s+precision|boolean|date|timestamp\s+with\s+time\s+zone)\b",
            table_match.group(1),
            flags=re.IGNORECASE | re.MULTILINE,
        )
    )
    missing_columns = sorted(set(STORE_INSERT_COLUMNS) - columns)
    if missing_columns:
        raise StorePublishingError(
            f"migration에 게시 필수 컬럼이 없습니다: {missing_columns}"
        )

    source_types = _parse_constraint_values(sql, "stores_source_type_allowed")
    verification_statuses = _parse_constraint_values(
        sql,
        "stores_verification_status_allowed",
    )
    if not source_types or not verification_statuses:
        raise StorePublishingError("migration 허용값 제약을 읽을 수 없습니다.")
    return StoreSchema(columns, source_types, verification_statuses)


def _parse_constraint_values(sql: str, constraint_name: str) -> frozenset[str]:
    constraint_match = re.search(
        rf"constraint\s+{re.escape(constraint_name)}\s+check\s*\((.*?)\n\s*\)",
        sql,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if constraint_match is None:
        return frozenset()
    return frozenset(re.findall(r"'([^']+)'", constraint_match.group(1)))


def parse_coordinate(value: str, field: str, row_id: str) -> float:
    try:
        coordinate = float(value)
    except (TypeError, ValueError):
        raise StorePublishingError(
            f"좌표가 숫자가 아닙니다: {row_id}, {field}"
        ) from None
    limit = 90 if field == "latitude" else 180
    if not math.isfinite(coordinate) or not -limit <= coordinate <= limit:
        raise StorePublishingError(f"좌표 범위를 벗어났습니다: {row_id}, {field}")
    return coordinate


def normalize_store_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return re.sub(r"[\s\-()（）]+", "", normalized)
