#!/usr/bin/env python3
"""Apply an explicit, locally stored expansion approval allowlist atomically."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
import uuid
from collections import Counter
from pathlib import Path
from typing import Any, Mapping, Sequence
from zoneinfo import ZoneInfo


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from build_burger_style_review import ALLOWED_STYLES  # noqa: E402
from build_publish_expansion_review import OUTPUT_HEADERS  # noqa: E402
from store_publishing_common import (  # noqa: E402
    REVIEW_HEADERS,
    StorePublishingError,
    normalize_store_text,
    parse_coordinate,
    read_csv_rows,
    write_csv_rows,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_PUBLISH_REVIEW_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_store_publish_review.csv"
)
DEFAULT_EXPANSION_REVIEW_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_publish_expansion_review.csv"
)
DEFAULT_STYLE_REVIEW_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_style_review.csv"
)
DEFAULT_STAGING_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_stores_staging.csv"
)
DEFAULT_HOLD_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_staging_hold_report.csv"
)
DEFAULT_APPROVAL_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_burger_publish_expansion_approvals.json"
)

EXPECTED_REVIEW_ROWS = 24
EXPECTED_EXPANSION_ROWS = 23
EXPECTED_APPROVALS = 9
EXPECTED_FINAL_VERIFIED = 10
EXPECTED_FINAL_PENDING = 14
KST = ZoneInfo("Asia/Seoul")

STYLE_REQUIRED_HEADERS = {
    "storeId",
    "candidateId",
    "name",
    "address",
    "proposedBurgerStyle",
    "reviewStatus",
}
STAGING_REQUIRED_HEADERS = {
    "candidateId",
    "displayName",
    "address",
    "latitude",
    "longitude",
}
HOLD_REQUIRED_HEADERS = {"candidateId", "name", "stagingStatus"}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _index_unique(
    rows: Sequence[Mapping[str, str]], field: str, label: str
) -> dict[str, Mapping[str, str]]:
    output: dict[str, Mapping[str, str]] = {}
    for row in rows:
        value = row.get(field, "").strip()
        if not value or value in output:
            raise StorePublishingError(f"{label}의 {field}가 비었거나 중복됐습니다.")
        output[value] = row
    return output


def _canonical_uuid(value: Any, label: str) -> str:
    try:
        return str(uuid.UUID(str(value or "").strip()))
    except ValueError:
        raise StorePublishingError(f"UUID가 올바르지 않습니다: {label}") from None


def _parse_date(value: Any, label: str, today: dt.date) -> str:
    try:
        parsed = dt.date.fromisoformat(str(value or "").strip())
    except ValueError:
        raise StorePublishingError(f"sourceAsOf가 YYYY-MM-DD가 아닙니다: {label}") from None
    if parsed > today:
        raise StorePublishingError(f"sourceAsOf가 미래 날짜입니다: {label}")
    return parsed.isoformat()


def _identity(record: Mapping[str, Any], label: str) -> tuple[str, str, str, str]:
    try:
        review_number = str(int(record.get("reviewNumber", "")))
    except (TypeError, ValueError):
        raise StorePublishingError(f"reviewNumber가 올바르지 않습니다: {label}") from None
    name = str(record.get("name") or "").strip()
    candidate_id = str(record.get("candidateId") or "").strip()
    store_id = _canonical_uuid(record.get("storeId"), label)
    if not name or not candidate_id:
        raise StorePublishingError(f"승인 식별 정보가 비었습니다: {label}")
    return review_number, name, store_id, candidate_id


def load_approval_manifest(
    path: Path, *, today: dt.date | None = None
) -> dict[str, Any]:
    today = today or dt.datetime.now(KST).date()
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise StorePublishingError(f"승인 명세를 읽을 수 없습니다: {path}") from error
    if not isinstance(payload, Mapping) or payload.get("version") != 1:
        raise StorePublishingError("승인 명세 version은 1이어야 합니다.")
    approvals = payload.get("approvals")
    denied = payload.get("denied")
    if not isinstance(approvals, list) or len(approvals) != EXPECTED_APPROVALS:
        raise StorePublishingError(f"승인 allowlist는 정확히 {EXPECTED_APPROVALS}곳이어야 합니다.")
    if not isinstance(denied, list) or not denied:
        raise StorePublishingError("명시적 denylist가 필요합니다.")

    parsed_approvals: list[dict[str, str]] = []
    approval_keys: set[tuple[str, str, str, str]] = set()
    approval_numbers: set[str] = set()
    approval_store_ids: set[str] = set()
    approval_candidate_ids: set[str] = set()
    for index, raw in enumerate(approvals, start=1):
        if not isinstance(raw, Mapping):
            raise StorePublishingError("승인 항목은 객체여야 합니다.")
        review_number, name, store_id, candidate_id = _identity(
            raw, f"approval {index}"
        )
        approved_style = str(raw.get("approvedStyle") or "").strip()
        if approved_style not in ALLOWED_STYLES or approved_style == "unclassified":
            raise StorePublishingError(f"승인 스타일이 올바르지 않습니다: {name}")
        source_as_of = _parse_date(raw.get("sourceAsOf"), name, today)
        source_basis = str(raw.get("sourceAsOfBasis") or "").strip()
        verification_note = str(raw.get("verificationNote") or "").strip()
        if not source_basis or not verification_note:
            raise StorePublishingError(f"게시 근거와 검수 메모가 필요합니다: {name}")
        if "사용자 승인" not in verification_note:
            raise StorePublishingError(f"검수 메모에 사용자 승인이 명시돼야 합니다: {name}")
        key = (review_number, name, store_id, candidate_id)
        if (
            key in approval_keys
            or review_number in approval_numbers
            or store_id in approval_store_ids
            or candidate_id in approval_candidate_ids
        ):
            raise StorePublishingError("승인 allowlist 식별자가 중복됐습니다.")
        approval_keys.add(key)
        approval_numbers.add(review_number)
        approval_store_ids.add(store_id)
        approval_candidate_ids.add(candidate_id)
        parsed_approvals.append(
            {
                "reviewNumber": review_number,
                "name": name,
                "storeId": store_id,
                "candidateId": candidate_id,
                "approvedStyle": approved_style,
                "sourceAsOf": source_as_of,
                "sourceAsOfBasis": source_basis,
                "verificationNote": verification_note,
            }
        )

    parsed_denied: list[dict[str, str]] = []
    denied_keys: set[tuple[str, str, str, str]] = set()
    for index, raw in enumerate(denied, start=1):
        if not isinstance(raw, Mapping):
            raise StorePublishingError("denylist 항목은 객체여야 합니다.")
        review_number, name, store_id, candidate_id = _identity(raw, f"denied {index}")
        key = (review_number, name, store_id, candidate_id)
        if key in denied_keys:
            raise StorePublishingError("denylist 식별자가 중복됐습니다.")
        if (
            review_number in approval_numbers
            or store_id in approval_store_ids
            or candidate_id in approval_candidate_ids
        ):
            raise StorePublishingError("denylist 매장이 승인 allowlist와 충돌합니다.")
        denied_keys.add(key)
        parsed_denied.append(
            {
                "reviewNumber": review_number,
                "name": name,
                "storeId": store_id,
                "candidateId": candidate_id,
            }
        )
    return {"version": 1, "approvals": parsed_approvals, "denied": parsed_denied}


def _same_text(left: str, right: str) -> bool:
    return normalize_store_text(left) == normalize_store_text(right)


def _assert_identity(
    expected: Mapping[str, str],
    row: Mapping[str, str],
    *,
    name_field: str = "name",
) -> None:
    candidate_id = expected["candidateId"]
    mismatches: list[str] = []
    if not _same_text(expected["name"], row.get(name_field, "")):
        mismatches.append("name")
    if expected["storeId"] != _canonical_uuid(row.get("storeId"), candidate_id):
        mismatches.append("storeId")
    if candidate_id != row.get("candidateId", "").strip():
        mismatches.append("candidateId")
    if mismatches:
        raise StorePublishingError(
            f"승인 식별 정보가 일치하지 않습니다: {candidate_id}, {mismatches}"
        )


def _assert_store_fields_match(
    publish_row: Mapping[str, str],
    other_row: Mapping[str, str],
    *,
    name_field: str,
) -> None:
    candidate_id = publish_row["candidateId"].strip()
    mismatches: list[str] = []
    if not _same_text(publish_row["name"], other_row.get(name_field, "")):
        mismatches.append("name")
    if not _same_text(publish_row["address"], other_row.get("address", "")):
        mismatches.append("address")
    for field in ("latitude", "longitude"):
        if parse_coordinate(publish_row[field], field, candidate_id) != parse_coordinate(
            other_row.get(field, ""), field, candidate_id
        ):
            mismatches.append(field)
    if mismatches:
        raise StorePublishingError(
            f"게시 입력의 매장 정보가 일치하지 않습니다: {candidate_id}, {mismatches}"
        )


def _parse_verified_at(now: dt.datetime | None) -> str:
    value = now or dt.datetime.now(KST)
    if value.tzinfo is None or value.utcoffset() is None:
        raise StorePublishingError("verifiedAt 생성 시각에는 시간대가 필요합니다.")
    return value.astimezone(KST).replace(microsecond=0).isoformat()


def apply_publish_expansion_approvals(
    publish_review_path: Path,
    expansion_review_path: Path,
    style_review_path: Path,
    staging_path: Path,
    hold_path: Path,
    approval_path: Path,
    *,
    now: dt.datetime | None = None,
) -> list[dict[str, str]]:
    protected_paths = (expansion_review_path, style_review_path, staging_path, hold_path)
    protected_hashes = {path: file_sha256(path) for path in protected_paths}
    manifest = load_approval_manifest(
        approval_path, today=(now.astimezone(KST).date() if now else None)
    )

    publish_headers, publish_rows = read_csv_rows(
        publish_review_path, set(REVIEW_HEADERS)
    )
    expansion_headers, expansion_rows = read_csv_rows(
        expansion_review_path, set(OUTPUT_HEADERS)
    )
    _, style_rows = read_csv_rows(style_review_path, STYLE_REQUIRED_HEADERS)
    _, staging_rows = read_csv_rows(staging_path, STAGING_REQUIRED_HEADERS)
    _, hold_rows = read_csv_rows(hold_path, HOLD_REQUIRED_HEADERS)
    if publish_headers != list(REVIEW_HEADERS):
        raise StorePublishingError("게시 검수표 컬럼 또는 순서가 다릅니다.")
    if expansion_headers != list(OUTPUT_HEADERS):
        raise StorePublishingError("확장 검수표 컬럼 또는 순서가 다릅니다.")
    if len(publish_rows) != EXPECTED_REVIEW_ROWS or len(expansion_rows) != EXPECTED_EXPANSION_ROWS:
        raise StorePublishingError("게시 또는 확장 검수표 행 수가 예상과 다릅니다.")

    publish_by_candidate = _index_unique(publish_rows, "candidateId", "게시 검수표")
    expansion_by_number = _index_unique(expansion_rows, "reviewNumber", "확장 검수표")
    style_by_candidate = _index_unique(style_rows, "candidateId", "스타일 검수표")
    staging_by_candidate = _index_unique(staging_rows, "candidateId", "staging")
    hold_by_candidate = _index_unique(hold_rows, "candidateId", "hold report")
    if len({_canonical_uuid(row["storeId"], row["candidateId"]) for row in publish_rows}) != len(publish_rows):
        raise StorePublishingError("게시 검수표 storeId가 중복됐습니다.")

    output = [dict(row) for row in publish_rows]
    output_by_candidate = {row["candidateId"].strip(): row for row in output}
    approved_ids = {row["candidateId"] for row in manifest["approvals"]}
    untouched_before = {
        row["candidateId"].strip(): dict(row)
        for row in publish_rows
        if row["candidateId"].strip() not in approved_ids
    }

    states: set[str] = set()
    for approval in manifest["approvals"]:
        candidate_id = approval["candidateId"]
        expansion_row = expansion_by_number.get(approval["reviewNumber"])
        publish_row = output_by_candidate.get(candidate_id)
        style_row = style_by_candidate.get(candidate_id)
        staging_row = staging_by_candidate.get(candidate_id)
        if not all((expansion_row, publish_row, style_row, staging_row)):
            raise StorePublishingError(f"승인 매장을 입력에서 찾을 수 없습니다: {candidate_id}")
        if candidate_id in hold_by_candidate:
            raise StorePublishingError(f"hold 매장은 승인할 수 없습니다: {candidate_id}")
        _assert_identity(approval, expansion_row)
        _assert_identity(approval, publish_row)
        _assert_identity(approval, style_row)
        if staging_row.get("candidateId", "").strip() != candidate_id or not _same_text(
            approval["name"], staging_row.get("displayName", "")
        ):
            raise StorePublishingError(f"staging 식별 정보가 다릅니다: {candidate_id}")
        _assert_store_fields_match(publish_row, expansion_row, name_field="name")
        _assert_store_fields_match(publish_row, staging_row, name_field="displayName")
        if expansion_row.get("recommendedDecision", "").strip() != "ready_for_user_approval":
            raise StorePublishingError(f"승인 권고 대상이 아닙니다: {candidate_id}")
        if expansion_row.get("currentPublishDecision", "").strip() != "pending" or expansion_row.get("currentIsActive", "").strip().lower() != "false":
            raise StorePublishingError(f"Phase 6A-1 기준 상태가 pending/false가 아닙니다: {candidate_id}")
        if style_row.get("reviewStatus", "").strip() != "approved" or style_row.get("proposedBurgerStyle", "").strip() != approval["approvedStyle"]:
            raise StorePublishingError(f"승인 스타일이 검수표와 다릅니다: {candidate_id}")

        decision = publish_row.get("publishDecision", "").strip()
        active = publish_row.get("isActive", "").strip().lower()
        if decision == "pending" and active == "false":
            states.add("pending")
        elif decision == "verified" and active == "true":
            states.add("verified")
        else:
            raise StorePublishingError(f"승인 전 상태가 안전하지 않습니다: {candidate_id}")

    if len(states) != 1:
        raise StorePublishingError("승인 9곳에 부분 반영 상태가 감지됐습니다.")
    verified_at = _parse_verified_at(now) if states == {"pending"} else ""

    for approval in manifest["approvals"]:
        row = output_by_candidate[approval["candidateId"]]
        if states == {"pending"}:
            row.update(
                {
                    "burgerStyle": approval["approvedStyle"],
                    "sourceAsOf": approval["sourceAsOf"],
                    "publishDecision": "verified",
                    "isActive": "true",
                    "verifiedAt": verified_at,
                    "verificationNote": approval["verificationNote"],
                }
            )
        else:
            expected = {
                "burgerStyle": approval["approvedStyle"],
                "sourceAsOf": approval["sourceAsOf"],
                "publishDecision": "verified",
                "isActive": "true",
                "verificationNote": approval["verificationNote"],
            }
            mismatches = [field for field, value in expected.items() if row.get(field, "").strip() != value]
            if mismatches or not row.get("verifiedAt", "").strip():
                raise StorePublishingError(
                    f"기존 승인 값이 명세와 다릅니다: {approval['candidateId']}, {mismatches}"
                )

    for denied in manifest["denied"]:
        expansion_row = expansion_by_number.get(denied["reviewNumber"])
        publish_row = output_by_candidate.get(denied["candidateId"])
        style_row = style_by_candidate.get(denied["candidateId"])
        if not all((expansion_row, publish_row, style_row)):
            raise StorePublishingError("denylist 매장을 입력에서 찾을 수 없습니다.")
        _assert_identity(denied, expansion_row)
        _assert_identity(denied, publish_row)
        if expansion_row.get("recommendedDecision", "").strip() != "needs_manual_check":
            raise StorePublishingError("denylist 매장의 수동 확인 상태가 바뀌었습니다.")
        if publish_row.get("publishDecision", "").strip() != "pending" or publish_row.get("isActive", "").strip().lower() != "false":
            raise StorePublishingError("denylist 매장이 pending/false가 아닙니다.")
        original = untouched_before[denied["candidateId"]]
        if publish_row != original:
            raise StorePublishingError("denylist 매장의 게시 값이 변경됐습니다.")

    if any(output_by_candidate[candidate_id] != original for candidate_id, original in untouched_before.items()):
        raise StorePublishingError("승인되지 않은 게시 검수표 행이 변경됐습니다.")
    decisions = Counter(row["publishDecision"].strip() for row in output)
    active_count = sum(row["isActive"].strip().lower() == "true" for row in output)
    if decisions != {"verified": EXPECTED_FINAL_VERIFIED, "pending": EXPECTED_FINAL_PENDING}:
        raise StorePublishingError(f"최종 게시 상태 집계가 다릅니다: {dict(decisions)}")
    if active_count != EXPECTED_FINAL_VERIFIED:
        raise StorePublishingError("최종 활성 매장 수가 10곳이 아닙니다.")

    if states == {"pending"}:
        write_csv_rows(publish_review_path, REVIEW_HEADERS, output)
    if protected_hashes != {path: file_sha256(path) for path in protected_paths}:
        raise StorePublishingError("보호 입력 파일의 SHA-256이 변경됐습니다.")
    return output


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="명시적으로 승인된 공개 확대 9곳을 원자적으로 반영합니다.")
    parser.add_argument("--publish-review", type=Path, default=DEFAULT_PUBLISH_REVIEW_PATH)
    parser.add_argument("--expansion-review", type=Path, default=DEFAULT_EXPANSION_REVIEW_PATH)
    parser.add_argument("--style-review", type=Path, default=DEFAULT_STYLE_REVIEW_PATH)
    parser.add_argument("--staging", type=Path, default=DEFAULT_STAGING_PATH)
    parser.add_argument("--hold-report", type=Path, default=DEFAULT_HOLD_PATH)
    parser.add_argument("--approvals", type=Path, default=DEFAULT_APPROVAL_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows = apply_publish_expansion_approvals(
            args.publish_review,
            args.expansion_review,
            args.style_review,
            args.staging,
            args.hold_report,
            args.approvals,
        )
        print(
            json.dumps(
                {
                    "reviewRows": len(rows),
                    "verifiedRows": sum(row["publishDecision"] == "verified" for row in rows),
                    "pendingRows": sum(row["publishDecision"] == "pending" for row in rows),
                    "activeRows": sum(row["isActive"] == "true" for row in rows),
                    "outputPath": str(args.publish_review.resolve()),
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
