#!/usr/bin/env python3
"""Apply sourcePlaceId-based manual review decisions to Kakao discovery CSV."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Mapping, Sequence


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_discovery.csv"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_discovery_reviewed.csv"
)
DEFAULT_DECISIONS_PATH = (
    PROJECT_ROOT
    / "data"
    / "config"
    / "kakao_manual_review_decisions.json"
)
MANUAL_REVIEW_HEADERS = (
    "manualReviewStatus",
    "manualReviewAction",
    "manualReviewNote",
)
VALID_STATUSES = {"pending", "needs_recheck", "rejected"}
VALID_ACTIONS = {
    "link_existing",
    "add_pending",
    "needs_address_check",
    "reject",
}
VALID_STATUS_ACTIONS = {
    ("pending", "link_existing"),
    ("pending", "add_pending"),
    ("needs_recheck", "needs_address_check"),
    ("rejected", "reject"),
}
VALID_DUPLICATE_DECISIONS = {"same_store", "false_duplicate"}


class ManualReviewError(ValueError):
    """Raised when manual review input or decisions fail validation."""


def load_decisions(path: Path) -> tuple[int, dict[str, dict[str, str]]]:
    try:
        with path.open("r", encoding="utf-8-sig") as decisions_file:
            data = json.load(decisions_file)
    except OSError as error:
        raise ManualReviewError(f"결정 파일을 열 수 없습니다: {path}") from error
    except json.JSONDecodeError as error:
        raise ManualReviewError(f"결정 파일 JSON이 올바르지 않습니다: {path}") from error

    expected_rows = data.get("expectedInputRows")
    entries = data.get("decisions")
    if not isinstance(expected_rows, int) or expected_rows < 1:
        raise ManualReviewError("expectedInputRows가 올바르지 않습니다.")
    if not isinstance(entries, list):
        raise ManualReviewError("decisions가 목록이 아닙니다.")

    decisions: dict[str, dict[str, str]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ManualReviewError("수동 검수 결정 항목이 객체가 아닙니다.")
        required = {
            "sourcePlaceId",
            "expectedName",
            "manualReviewStatus",
            "manualReviewAction",
            "manualReviewNote",
        }
        if not required.issubset(entry):
            raise ManualReviewError("수동 검수 결정에 필수 필드가 없습니다.")
        if not all(isinstance(entry[key], str) for key in required):
            raise ManualReviewError("수동 검수 결정 필드는 문자열이어야 합니다.")
        source_place_id = entry["sourcePlaceId"].strip()
        status = entry["manualReviewStatus"]
        action = entry["manualReviewAction"]
        if not source_place_id or source_place_id in decisions:
            raise ManualReviewError(
                f"sourcePlaceId가 비어 있거나 중복됐습니다: {source_place_id}"
            )
        if status not in VALID_STATUSES or action not in VALID_ACTIONS:
            raise ManualReviewError(
                f"허용되지 않은 상태 또는 작업입니다: {source_place_id}"
            )
        if (status, action) not in VALID_STATUS_ACTIONS:
            raise ManualReviewError(
                f"상태와 작업 조합이 올바르지 않습니다: {source_place_id}"
            )
        duplicate_decision = entry.get("possibleDuplicateDecision", "")
        if duplicate_decision and duplicate_decision not in VALID_DUPLICATE_DECISIONS:
            raise ManualReviewError(
                f"possibleDuplicateDecision이 올바르지 않습니다: {source_place_id}"
            )
        decisions[source_place_id] = {
            key: str(value) for key, value in entry.items()
        }

    if len(decisions) != expected_rows:
        raise ManualReviewError(
            f"결정 수가 expectedInputRows와 다릅니다: {len(decisions)} != {expected_rows}"
        )
    return expected_rows, decisions


def read_input(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            reader = csv.DictReader(input_file)
            fieldnames = list(reader.fieldnames or [])
            rows = list(reader)
    except OSError as error:
        raise ManualReviewError(f"원본 CSV를 열 수 없습니다: {path}") from error
    if not {"sourcePlaceId", "discoveryId", "name", "matchStatus"}.issubset(
        fieldnames
    ):
        raise ManualReviewError("원본 CSV에 필수 필드가 없습니다.")
    if any(field in fieldnames for field in MANUAL_REVIEW_HEADERS):
        raise ManualReviewError("원본 CSV에 수동 검수 필드가 이미 있습니다.")
    return fieldnames, rows


def apply_manual_reviews(
    input_path: Path,
    output_path: Path,
    decisions_path: Path,
    *,
    overwrite: bool = False,
) -> tuple[list[dict[str, str]], Counter[str], Counter[str]]:
    if output_path.exists() and not overwrite:
        raise ManualReviewError(
            f"출력 파일이 이미 존재합니다. 덮어쓰지 않았습니다: {output_path}"
        )
    expected_rows, decisions = load_decisions(decisions_path)
    original_headers, rows = read_input(input_path)
    if len(rows) != expected_rows:
        raise ManualReviewError(
            f"입력 행 수가 예상과 다릅니다: {len(rows)} != {expected_rows}"
        )

    source_place_ids = [row["sourcePlaceId"].strip() for row in rows]
    discovery_ids = [row["discoveryId"].strip() for row in rows]
    if len(set(source_place_ids)) != len(source_place_ids):
        raise ManualReviewError("원본 sourcePlaceId가 중복됐습니다.")
    if len(set(discovery_ids)) != len(discovery_ids):
        raise ManualReviewError("원본 discoveryId가 중복됐습니다.")
    input_ids = set(source_place_ids)
    decision_ids = set(decisions)
    if input_ids != decision_ids:
        missing = sorted(input_ids - decision_ids)
        unknown = sorted(decision_ids - input_ids)
        raise ManualReviewError(
            f"결정 ID가 원본과 일치하지 않습니다. 누락={missing}, 미확인={unknown}"
        )

    output_rows: list[dict[str, str]] = []
    status_counts: Counter[str] = Counter()
    action_counts: Counter[str] = Counter()
    for row in rows:
        source_place_id = row["sourcePlaceId"].strip()
        decision = decisions[source_place_id]
        if row["name"] != decision["expectedName"]:
            raise ManualReviewError(
                f"ID와 예상 매장명이 일치하지 않습니다: {source_place_id}"
            )
        duplicate_decision = decision.get("possibleDuplicateDecision", "")
        if duplicate_decision and row["matchStatus"] != "possible_duplicate":
            raise ManualReviewError(
                f"possible_duplicate 재판정 대상의 원본 상태가 다릅니다: {source_place_id}"
            )

        output_row = dict(row)
        output_row["manualReviewStatus"] = decision["manualReviewStatus"]
        output_row["manualReviewAction"] = decision["manualReviewAction"]
        output_row["manualReviewNote"] = decision["manualReviewNote"]
        output_rows.append(output_row)
        status_counts[decision["manualReviewStatus"]] += 1
        action_counts[decision["manualReviewAction"]] += 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_headers = original_headers + list(MANUAL_REVIEW_HEADERS)
    with output_path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=output_headers)
        writer.writeheader()
        writer.writerows(output_rows)
    return output_rows, status_counts, action_counts


def summarize_possible_duplicates(
    decisions: Mapping[str, Mapping[str, str]],
) -> dict[str, list[str]]:
    result = {"same_store": [], "false_duplicate": []}
    for source_place_id, decision in decisions.items():
        classification = decision.get("possibleDuplicateDecision", "")
        if classification in result:
            result[classification].append(source_place_id)
    for values in result.values():
        values.sort(key=int)
    return result


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="카카오 보완 후보에 sourcePlaceId 기반 수동 검수 결과를 적용합니다."
    )
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--decisions", type=Path, default=DEFAULT_DECISIONS_PATH)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows, status_counts, action_counts = apply_manual_reviews(
            args.input,
            args.output,
            args.decisions,
            overwrite=args.overwrite,
        )
        _, decisions = load_decisions(args.decisions)
        summary = {
            "입력 행 수": len(rows),
            "출력 행 수": len(rows),
            "manualReviewStatus": dict(sorted(status_counts.items())),
            "manualReviewAction": dict(sorted(action_counts.items())),
            "possible_duplicate 재판정": summarize_possible_duplicates(decisions),
            "출력 경로": str(args.output.resolve()),
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0
    except ManualReviewError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
