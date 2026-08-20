#!/usr/bin/env python3
"""Convert review-only staging CSV rows to a minimal Flutter development asset."""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path
from typing import Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from build_burger_style_review import (  # noqa: E402
    ALLOWED_STYLES,
    read_validated_style_review_rows,
)
from store_publishing_common import normalize_store_text  # noqa: E402


EXPECTED_ROWS = 24
ALLOWED_OUTPUT_FIELDS = {
    "id",
    "name",
    "address",
    "latitude",
    "longitude",
    "burgerStyle",
    "verificationStatus",
}
FORBIDDEN_INPUT_NAMES = {
    "다운타우너 한남",
    "잭잭",
    "버거운녀석들",
    "로스니버거",
}
REQUIRED_INPUT_FIELDS = {
    "candidateId",
    "displayName",
    "address",
    "latitude",
    "longitude",
    "stagingStatus",
    "verificationStatus",
}


class FlutterAssetError(ValueError):
    """Raised when staging data is unsafe to bundle into the Flutter debug app."""


def read_staging_rows(path: Path) -> list[dict[str, str]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            reader = csv.DictReader(input_file)
            headers = set(reader.fieldnames or [])
            rows = list(reader)
    except OSError as error:
        raise FlutterAssetError(f"staging CSV를 열 수 없습니다: {path}") from error
    missing_headers = sorted(REQUIRED_INPUT_FIELDS - headers)
    if missing_headers:
        raise FlutterAssetError(f"staging CSV 필수 컬럼이 없습니다: {missing_headers}")
    return rows


def parse_coordinate(value: str, field: str, candidate_id: str) -> float:
    try:
        coordinate = float(value)
    except ValueError:
        raise FlutterAssetError(
            f"좌표가 숫자가 아닙니다: {candidate_id}, {field}"
        ) from None
    limit = 90 if field == "latitude" else 180
    if not math.isfinite(coordinate) or coordinate == 0 or not -limit <= coordinate <= limit:
        raise FlutterAssetError(f"좌표가 유효하지 않습니다: {candidate_id}, {field}")
    return coordinate


def _style_overrides(
    rows: Sequence[Mapping[str, str]],
    style_review_rows: Sequence[Mapping[str, str]],
) -> dict[str, str]:
    if len(style_review_rows) != len(rows):
        raise FlutterAssetError("staging과 스타일 검수표 행 수가 다릅니다.")
    style_by_candidate: dict[str, Mapping[str, str]] = {}
    for style_row in style_review_rows:
        candidate_id = style_row.get("candidateId", "").strip()
        if not candidate_id or candidate_id in style_by_candidate:
            raise FlutterAssetError(
                f"스타일 검수표 candidateId가 비었거나 중복됐습니다: {candidate_id}"
            )
        style_by_candidate[candidate_id] = style_row

    staging_ids = {row.get("candidateId", "").strip() for row in rows}
    if staging_ids != set(style_by_candidate):
        raise FlutterAssetError("staging과 스타일 검수표 candidateId 집합이 다릅니다.")

    overrides: dict[str, str] = {}
    for row in rows:
        candidate_id = row.get("candidateId", "").strip()
        style_row = style_by_candidate[candidate_id]
        expected_name = row.get("displayName", "").strip()
        expected_address = row.get("address", "").strip()
        if normalize_store_text(style_row.get("name", "")) != normalize_store_text(
            expected_name
        ):
            raise FlutterAssetError(f"스타일 검수표 이름이 다릅니다: {candidate_id}")
        if normalize_store_text(
            style_row.get("address", "")
        ) != normalize_store_text(expected_address):
            raise FlutterAssetError(f"스타일 검수표 주소가 다릅니다: {candidate_id}")
        if style_row.get("reviewStatus", "").strip() == "approved":
            style = style_row.get("proposedBurgerStyle", "").strip()
            if style not in ALLOWED_STYLES or style == "unclassified":
                raise FlutterAssetError(
                    f"승인 스타일이 올바르지 않습니다: {candidate_id}, {style}"
                )
            overrides[candidate_id] = style
        else:
            overrides[candidate_id] = "unclassified"
    return overrides


def convert_rows(
    rows: Sequence[Mapping[str, str]],
    style_review_rows: Sequence[Mapping[str, str]] | None = None,
) -> list[dict[str, object]]:
    if len(rows) != EXPECTED_ROWS:
        raise FlutterAssetError(f"staging 행 수가 정확히 24개가 아닙니다: {len(rows)}")
    style_overrides = (
        _style_overrides(rows, style_review_rows)
        if style_review_rows is not None
        else None
    )
    output: list[dict[str, object]] = []
    seen_ids: set[str] = set()
    for row in rows:
        candidate_id = row.get("candidateId", "").strip()
        name = row.get("displayName", "").strip()
        address = row.get("address", "").strip()
        if not candidate_id or candidate_id in seen_ids:
            raise FlutterAssetError(f"candidateId가 비었거나 중복됐습니다: {candidate_id}")
        if not name or not address:
            raise FlutterAssetError(f"이름 또는 주소가 비었습니다: {candidate_id}")
        if name in FORBIDDEN_INPUT_NAMES:
            raise FlutterAssetError(f"보류 매장은 Flutter staging에 포함할 수 없습니다: {name}")
        if row.get("stagingStatus") != "candidate_pending":
            raise FlutterAssetError(f"허용되지 않은 stagingStatus입니다: {candidate_id}")
        if row.get("verificationStatus") != "pending":
            raise FlutterAssetError(f"pending 외 verificationStatus입니다: {candidate_id}")
        latitude = parse_coordinate(row.get("latitude", ""), "latitude", candidate_id)
        longitude = parse_coordinate(
            row.get("longitude", ""), "longitude", candidate_id
        )
        item: dict[str, object] = {
            "id": candidate_id,
            "name": name,
            "address": address,
            "latitude": latitude,
            "longitude": longitude,
            "burgerStyle": (
                style_overrides[candidate_id]
                if style_overrides is not None
                else "미분류"
            ),
            "verificationStatus": "pending",
        }
        if set(item) != ALLOWED_OUTPUT_FIELDS:
            raise FlutterAssetError("Flutter JSON 허용 필드 검증에 실패했습니다.")
        output.append(item)
        seen_ids.add(candidate_id)
    return output


def write_asset(
    input_path: Path,
    output_path: Path,
    *,
    overwrite: bool = False,
    style_review_path: Path | None = None,
) -> list[dict[str, object]]:
    if output_path.exists() and not overwrite:
        raise FlutterAssetError(f"출력 JSON이 이미 존재합니다: {output_path}")
    rows = read_staging_rows(input_path)
    try:
        style_review_rows = (
            read_validated_style_review_rows(style_review_path)
            if style_review_path is not None
            else None
        )
    except ValueError as error:
        raise FlutterAssetError(str(error)) from error
    output = convert_rows(rows, style_review_rows)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_name(f".{output_path.name}.tmp")
    try:
        temporary_path.write_text(
            json.dumps(output, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        saved = json.loads(temporary_path.read_text(encoding="utf-8"))
        if not isinstance(saved, list) or any(
            not isinstance(item, dict) or set(item) != ALLOWED_OUTPUT_FIELDS
            for item in saved
        ):
            raise FlutterAssetError("저장된 Flutter JSON 필드 검증에 실패했습니다.")
        temporary_path.replace(output_path)
    except (OSError, json.JSONDecodeError) as error:
        temporary_path.unlink(missing_ok=True)
        raise FlutterAssetError("Flutter JSON을 안전하게 저장할 수 없습니다.") from error
    except FlutterAssetError:
        temporary_path.unlink(missing_ok=True)
        raise
    return output


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="pending staging CSV를 최소 Flutter 개발용 JSON으로 변환합니다."
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--style-review", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        output = write_asset(
            args.input,
            args.output,
            overwrite=args.overwrite,
            style_review_path=args.style_review,
        )
        print(
            json.dumps(
                {
                    "convertedRows": len(output),
                    "outputFields": sorted(ALLOWED_OUTPUT_FIELDS),
                    "outputPath": str(args.output.resolve()),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except FlutterAssetError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
