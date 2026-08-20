#!/usr/bin/env python3
"""Apply only explicitly supplied human approvals to a style review CSV."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from build_burger_style_review import (  # noqa: E402
    ALLOWED_STYLES,
    DEFAULT_OUTPUT_PATH,
    STYLE_REVIEW_HEADERS,
    read_validated_style_review_rows,
    validate_style_review_rows,
)
from store_publishing_common import StorePublishingError, write_csv_rows  # noqa: E402


APPROVAL_NOTE_PREFIX = "사용자 명시적 승인(Phase 4C-B2)"


def parse_approval_values(values: Sequence[str]) -> dict[str, str]:
    approvals: dict[str, str] = {}
    for value in values:
        review_number, separator, style = value.partition("=")
        review_number = review_number.strip()
        style = style.strip()
        if not separator or not review_number.isdigit() or style not in ALLOWED_STYLES:
            raise StorePublishingError(
                f"승인 인수는 reviewNumber=style 형식이어야 합니다: {value}"
            )
        if review_number in approvals:
            raise StorePublishingError(f"승인 번호가 중복됐습니다: {review_number}")
        approvals[review_number] = style
    if not approvals:
        raise StorePublishingError("명시적으로 전달된 스타일 승인이 없습니다.")
    return approvals


def apply_approvals(
    rows: Sequence[Mapping[str, str]],
    approvals: Mapping[str, str],
) -> list[dict[str, str]]:
    known_numbers = {row.get("reviewNumber", "").strip() for row in rows}
    unknown_numbers = sorted(set(approvals) - known_numbers, key=int)
    if unknown_numbers:
        raise StorePublishingError(f"검수표에 없는 승인 번호입니다: {unknown_numbers}")

    output: list[dict[str, str]] = []
    for raw_row in rows:
        row = dict(raw_row)
        review_number = row["reviewNumber"].strip()
        approved_style = approvals.get(review_number)
        if approved_style is None:
            if row.get("reviewStatus", "").strip() == "approved":
                raise StorePublishingError(
                    f"승인 목록 밖의 approved 행이 있습니다: {review_number}"
                )
            output.append(row)
            continue

        if row.get("proposedBurgerStyle", "").strip() != approved_style:
            raise StorePublishingError(
                f"사용자 승인 스타일과 검수표 제안이 다릅니다: {review_number}"
            )
        if row.get("approvalRecommendation", "").strip() != (
            "ready_for_user_approval"
        ):
            raise StorePublishingError(
                f"승인 준비가 되지 않은 행은 승인할 수 없습니다: {review_number}"
            )
        if row.get("sourceAgreement", "").strip() != "consistent":
            raise StorePublishingError(
                f"출처가 일치하지 않는 행은 승인할 수 없습니다: {review_number}"
            )

        approval_note = f"{APPROVAL_NOTE_PREFIX}: {approved_style}."
        reviewer_note = row.get("reviewerNote", "").strip()
        if approval_note not in reviewer_note:
            row["reviewerNote"] = "; ".join(
                note for note in (reviewer_note, approval_note) if note
            )
        row["reviewStatus"] = "approved"
        output.append(row)
    return output


def apply_approvals_to_file(path: Path, approvals: Mapping[str, str]) -> int:
    rows = read_validated_style_review_rows(path)
    output = apply_approvals(rows, approvals)
    validate_style_review_rows(output)
    write_csv_rows(path, STYLE_REVIEW_HEADERS, output)
    validated = read_validated_style_review_rows(path)
    approved_count = sum(row["reviewStatus"] == "approved" for row in validated)
    if approved_count != len(approvals):
        raise StorePublishingError("승인 결과 행 수가 명시적 승인 수와 다릅니다.")
    return approved_count


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="명시적으로 전달된 사용자 버거 스타일 승인만 반영합니다."
    )
    parser.add_argument("--review", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument(
        "--approve",
        action="append",
        default=[],
        metavar="NUMBER=STYLE",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        approvals = parse_approval_values(args.approve)
        approved_rows = apply_approvals_to_file(args.review, approvals)
        print(
            json.dumps(
                {
                    "approvedRows": approved_rows,
                    "reviewPath": str(args.review.resolve()),
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
