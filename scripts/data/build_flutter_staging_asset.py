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


def convert_rows(rows: Sequence[Mapping[str, str]]) -> list[dict[str, object]]:
    if len(rows) != EXPECTED_ROWS:
        raise FlutterAssetError(f"staging 행 수가 정확히 24개가 아닙니다: {len(rows)}")
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
            "burgerStyle": "미분류",
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
) -> list[dict[str, object]]:
    if output_path.exists() and not overwrite:
        raise FlutterAssetError(f"출력 JSON이 이미 존재합니다: {output_path}")
    rows = read_staging_rows(input_path)
    output = convert_rows(rows)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    saved = json.loads(output_path.read_text(encoding="utf-8"))
    if not isinstance(saved, list) or any(
        not isinstance(item, dict) or set(item) != ALLOWED_OUTPUT_FIELDS
        for item in saved
    ):
        raise FlutterAssetError("저장된 Flutter JSON 필드 검증에 실패했습니다.")
    return output


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="pending staging CSV를 최소 Flutter 개발용 JSON으로 변환합니다."
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        output = write_asset(args.input, args.output, overwrite=args.overwrite)
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
