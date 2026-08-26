#!/usr/bin/env python3
"""Apply an explicit Phase 6B-2 burger-style correction to the local review."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from apply_phase_6b2_store_approvals import (  # noqa: E402
    DEFAULT_APPROVAL_PATH,
    DEFAULT_PUBLISH_PATH,
    EXPECTED_FINAL_PENDING,
    EXPECTED_FINAL_PUBLIC,
    EXPECTED_FINAL_ROWS,
    file_sha256,
    load_phase_6b2_approval_manifest,
)
from store_publishing_common import (  # noqa: E402
    REVIEW_HEADERS,
    StorePublishingError,
    normalize_store_text,
    parse_coordinate,
    read_csv_rows,
    write_csv_rows,
)


def load_style_correction(
    approval_path: Path, *, today: dt.date
) -> dict[str, Any]:
    approvals, _ = load_phase_6b2_approval_manifest(approval_path, today=today)
    corrections = [item for item in approvals if item["styleCorrectionFrom"]]
    if len(corrections) != 1:
        raise StorePublishingError(
            "Exactly one Phase 6B-2 style correction must be declared."
        )
    return corrections[0]


def _same_identity(row: Mapping[str, str], correction: Mapping[str, Any]) -> bool:
    return (
        row["storeId"].strip() == correction["storeId"]
        and row["candidateId"].strip() == correction["candidateId"]
        and normalize_store_text(row["name"])
        == normalize_store_text(str(correction["name"]))
        and normalize_store_text(row["address"])
        == normalize_store_text(str(correction["address"]))
    )


def apply_phase_6b2_style_correction(
    review_path: Path,
    approval_path: Path,
    *,
    today: dt.date | None = None,
) -> tuple[list[dict[str, str]], bool]:
    effective_date = today or dt.datetime.now(dt.timezone.utc).date()
    approval_hash = file_sha256(approval_path)
    correction = load_style_correction(approval_path, today=effective_date)
    headers, rows = read_csv_rows(review_path, set(REVIEW_HEADERS))
    if headers != list(REVIEW_HEADERS):
        raise StorePublishingError("Publish review columns or order are invalid.")
    if len(rows) != EXPECTED_FINAL_ROWS:
        raise StorePublishingError("Publish review must contain exactly 26 rows.")

    by_candidate = {row["candidateId"].strip(): row for row in rows}
    if len(by_candidate) != len(rows):
        raise StorePublishingError("Publish review candidateId values must be unique.")
    store_ids = [row["storeId"].strip() for row in rows]
    if len(store_ids) != len(set(store_ids)):
        raise StorePublishingError("Publish review storeId values must be unique.")

    decisions = Counter(row["publishDecision"].strip() for row in rows)
    active_count = sum(row["isActive"].strip().lower() == "true" for row in rows)
    if decisions != {
        "verified": EXPECTED_FINAL_PUBLIC,
        "pending": EXPECTED_FINAL_PENDING,
    } or active_count != EXPECTED_FINAL_PUBLIC:
        raise StorePublishingError(
            "Publish review must remain at 25 verified/active and 1 pending/inactive."
        )

    target = by_candidate.get(correction["candidateId"])
    if target is None or not _same_identity(target, correction):
        raise StorePublishingError("Style correction target identity does not match.")
    if (
        target["publishDecision"].strip() != "verified"
        or target["isActive"].strip().lower() != "true"
    ):
        raise StorePublishingError("Style correction target must be verified and active.")
    label = correction["candidateId"]
    if parse_coordinate(target["latitude"], "latitude", label) != parse_coordinate(
        correction["latitude"], "latitude", label
    ) or parse_coordinate(
        target["longitude"], "longitude", label
    ) != parse_coordinate(correction["longitude"], "longitude", label):
        raise StorePublishingError("Style correction target coordinates do not match.")

    original_rows = [dict(row) for row in rows]
    current_style = target["burgerStyle"].strip()
    expected_style = str(correction["approvedStyle"])
    correction_from = str(correction["styleCorrectionFrom"])
    changed = False
    if current_style == correction_from:
        target["burgerStyle"] = expected_style
        changed = True
    elif current_style != expected_style:
        raise StorePublishingError(
            "Style correction target is neither the previous nor corrected style."
        )

    changed_fields: list[tuple[int, str]] = []
    for index, (before, after) in enumerate(zip(original_rows, rows, strict=True)):
        for field in REVIEW_HEADERS:
            if before[field] != after[field]:
                changed_fields.append((index, field))
    if changed and changed_fields != [
        (rows.index(target), "burgerStyle")
    ]:
        raise StorePublishingError("Style correction changed an unexpected field.")
    if not changed and changed_fields:
        raise StorePublishingError("Idempotent style correction changed review data.")

    if changed:
        write_csv_rows(review_path, REVIEW_HEADERS, rows)
    if file_sha256(approval_path) != approval_hash:
        raise StorePublishingError("Approval source changed during style correction.")
    return rows, changed


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--approvals", type=Path, default=DEFAULT_APPROVAL_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows, changed = apply_phase_6b2_style_correction(
            args.review, args.approvals
        )
        correction = load_style_correction(
            args.approvals, today=dt.datetime.now(dt.timezone.utc).date()
        )
        print(
            json.dumps(
                {
                    "changed": changed,
                    "name": correction["name"],
                    "from": correction["styleCorrectionFrom"],
                    "to": correction["approvedStyle"],
                    "reviewRows": len(rows),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except StorePublishingError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
