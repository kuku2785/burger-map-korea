#!/usr/bin/env python3
"""Generate a guarded one-row Phase 6B-2 burger-style correction SQL file.

If the output already exists, identical content is accepted. Different content
is never allowed to overwrite the existing SQL file.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import uuid
from pathlib import Path
from typing import Any, Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from apply_phase_6b2_store_approvals import (  # noqa: E402
    DEFAULT_APPROVAL_PATH,
    DEFAULT_PUBLISH_PATH,
    EXPECTED_FINAL_PUBLIC,
    file_sha256,
)
from apply_phase_6b2_style_correction import load_style_correction  # noqa: E402
from store_publishing_common import (  # noqa: E402
    REVIEW_HEADERS,
    StorePublishingError,
    normalize_store_text,
    read_csv_rows,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "staging"
    / "yongsan_burger_phase_6b2_jackjack_style_correction.sql"
)

FORBIDDEN_PATTERNS = re.compile(
    r"(?:candidateId|sourcePlaceId|discoveryId|reviewItemId|https?://|"
    r"AIza[0-9A-Za-z_-]{30,}|sb_(?:publishable|secret)_[0-9A-Za-z_-]{20,}|"
    r"eyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+|"
    r"\b(?:insert|delete|upsert|rpc)\b|on\s+conflict)",
    re.IGNORECASE,
)


def _sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _load_target(
    review_path: Path, approval_path: Path, *, today: dt.date
) -> tuple[dict[str, str], dict[str, Any]]:
    correction = load_style_correction(approval_path, today=today)
    headers, rows = read_csv_rows(review_path, set(REVIEW_HEADERS))
    if headers != list(REVIEW_HEADERS):
        raise StorePublishingError("Publish review columns or order are invalid.")
    public_rows = [
        row
        for row in rows
        if row["publishDecision"].strip() == "verified"
        and row["isActive"].strip().lower() == "true"
    ]
    if len(public_rows) != EXPECTED_FINAL_PUBLIC:
        raise StorePublishingError("Publish review must contain 25 public stores.")
    matches = [
        row
        for row in rows
        if row["candidateId"].strip() == correction["candidateId"]
    ]
    if len(matches) != 1:
        raise StorePublishingError("Style correction target must occur exactly once.")
    target = matches[0]
    try:
        if str(uuid.UUID(target["storeId"].strip())) != correction["storeId"]:
            raise ValueError
    except ValueError:
        raise StorePublishingError("Style correction target UUID does not match.") from None
    if (
        normalize_store_text(target["name"])
        != normalize_store_text(str(correction["name"]))
        or normalize_store_text(target["address"])
        != normalize_store_text(str(correction["address"]))
        or target["burgerStyle"].strip() != correction["approvedStyle"]
        or target["publishDecision"].strip() != "verified"
        or target["isActive"].strip().lower() != "true"
    ):
        raise StorePublishingError("Corrected review target does not match approval source.")
    return target, correction


def build_guarded_style_correction_sql(
    target: Mapping[str, str], correction: Mapping[str, Any]
) -> str:
    store_id = _sql_text(target["storeId"].strip())
    name = _sql_text(target["name"].strip())
    address = _sql_text(target["address"].strip())
    previous_style = _sql_text(str(correction["styleCorrectionFrom"]))
    corrected_style = _sql_text(str(correction["approvedStyle"]))
    predicates = (
        f"id = {store_id}::uuid\n"
        f"     and name = {name}\n"
        f"     and address = {address}\n"
        "     and verification_status = 'verified'\n"
        "     and is_active = true"
    )
    sql = (
        "begin;\n\n"
        "do $phase_6b2_style_correction$\n"
        "declare\n"
        "  public_count integer;\n"
        "  target_count integer;\n"
        "  changed_count integer;\n"
        "begin\n"
        "  select count(*) into public_count\n"
        "    from public.stores\n"
        "   where verification_status = 'verified' and is_active = true;\n"
        f"  if public_count <> {EXPECTED_FINAL_PUBLIC} then\n"
        "    raise exception 'Phase 6B-2 style correction precondition failed: expected 25 public stores.';\n"
        "  end if;\n\n"
        "  select count(*) into target_count\n"
        "    from public.stores\n"
        f"   where {predicates}\n"
        f"     and burger_style = {previous_style};\n"
        "  if target_count <> 1 then\n"
        "    raise exception 'Phase 6B-2 style correction precondition failed: expected exactly one target.';\n"
        "  end if;\n\n"
        "  update public.stores\n"
        f"     set burger_style = {corrected_style}\n"
        f"   where {predicates}\n"
        f"     and burger_style = {previous_style};\n"
        "  get diagnostics changed_count = row_count;\n"
        "  if changed_count <> 1 then\n"
        "    raise exception 'Phase 6B-2 style correction update count failed.';\n"
        "  end if;\n\n"
        "  select count(*) into target_count\n"
        "    from public.stores\n"
        f"   where {predicates}\n"
        f"     and burger_style = {corrected_style};\n"
        "  if target_count <> 1 then\n"
        "    raise exception 'Phase 6B-2 style correction postcondition failed: corrected target mismatch.';\n"
        "  end if;\n\n"
        "  select count(*) into public_count\n"
        "    from public.stores\n"
        "   where verification_status = 'verified' and is_active = true;\n"
        f"  if public_count <> {EXPECTED_FINAL_PUBLIC} then\n"
        "    raise exception 'Phase 6B-2 style correction postcondition failed: expected 25 public stores.';\n"
        "  end if;\n"
        "end\n"
        "$phase_6b2_style_correction$;\n\n"
        "commit;\n"
    )
    if FORBIDDEN_PATTERNS.search(sql):
        raise StorePublishingError("Generated style correction SQL contains forbidden data.")
    if sql.lower().count("update public.stores") != 1:
        raise StorePublishingError("Style correction SQL must contain exactly one UPDATE.")
    return sql


def generate_phase_6b2_style_correction_sql(
    review_path: Path,
    approval_path: Path,
    output_path: Path,
    *,
    today: dt.date | None = None,
) -> int:
    effective_date = today or dt.datetime.now(dt.timezone.utc).date()
    target, correction = _load_target(
        review_path, approval_path, today=effective_date
    )
    sql = build_guarded_style_correction_sql(target, correction)
    if output_path.exists():
        if output_path.read_text(encoding="utf-8") != sql:
            raise StorePublishingError(
                "Existing style correction SQL differs and will not be overwritten."
            )
        return 1
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_name(f".{output_path.name}.tmp")
    try:
        temporary_path.write_text(sql, encoding="utf-8")
        temporary_path.replace(output_path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise StorePublishingError(
            f"Cannot save style correction SQL: {output_path}"
        ) from error
    return 1


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--approvals", type=Path, default=DEFAULT_APPROVAL_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        count = generate_phase_6b2_style_correction_sql(
            args.review, args.approvals, args.output
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
        print(f"Error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
