#!/usr/bin/env python3
"""Apply explicit Phase 6B approvals to the local publish review."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
import uuid
from collections import Counter
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence
from zoneinfo import ZoneInfo


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from build_25_store_expansion_review import OUTPUT_HEADERS  # noqa: E402
from build_burger_style_review import ALLOWED_STYLES  # noqa: E402
from store_publishing_common import (  # noqa: E402
    REVIEW_HEADERS,
    StorePublishingError,
    normalize_store_text,
    parse_coordinate,
    read_csv_rows,
    write_csv_rows,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_PUBLISH_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_store_publish_review.csv"
)
DEFAULT_EXPANSION_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_25_store_expansion_review.csv"
)
DEFAULT_STYLE_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_style_review.csv"
)
DEFAULT_STAGING_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_stores_staging.csv"
)
DEFAULT_HOLD_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_staging_hold_report.csv"
)
DEFAULT_KAKAO_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_discovery_reviewed.csv"
)
DEFAULT_APPROVAL_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_burger_25_store_expansion_approvals.json"
)

EXPECTED_APPROVALS = 13
EXPECTED_PENDING_APPROVALS = 12
EXPECTED_HOLD_APPROVALS = 1
EXPECTED_INITIAL_ROWS = 24
EXPECTED_INITIAL_PUBLIC = 10
EXPECTED_INITIAL_PENDING = 14
EXPECTED_FINAL_ROWS = 25
EXPECTED_FINAL_PUBLIC = 23
EXPECTED_FINAL_PENDING = 2
KST = ZoneInfo("Asia/Seoul")

STYLE_HEADERS = {
    "storeId",
    "candidateId",
    "name",
    "address",
    "proposedBurgerStyle",
}
STAGING_HEADERS = {
    "candidateId",
    "displayName",
    "address",
    "latitude",
    "longitude",
}
HOLD_HEADERS = {
    "candidateId",
    "sourcePlaceId",
    "name",
    "previousStatus",
    "stagingStatus",
    "holdReason",
}
KAKAO_HEADERS = {
    "discoveryId",
    "sourcePlaceId",
    "name",
    "address",
    "latitude",
    "longitude",
}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _index_unique(
    rows: Sequence[Mapping[str, str]], field: str, label: str
) -> dict[str, Mapping[str, str]]:
    result: dict[str, Mapping[str, str]] = {}
    for row in rows:
        value = row.get(field, "").strip()
        if not value or value in result:
            raise StorePublishingError(f"{label}의 {field}가 비었거나 중복됐습니다.")
        result[value] = row
    return result


def _same_text(left: str, right: str) -> bool:
    return normalize_store_text(left) == normalize_store_text(right)


def _canonical_uuid(value: Any, label: str) -> str:
    try:
        return str(uuid.UUID(str(value or "").strip()))
    except ValueError:
        raise StorePublishingError(f"UUID가 올바르지 않습니다: {label}") from None


def _parse_date(value: Any, label: str, today: dt.date) -> str:
    try:
        parsed = dt.date.fromisoformat(str(value or "").strip())
    except ValueError:
        raise StorePublishingError(f"근거 기준일이 올바르지 않습니다: {label}") from None
    if parsed > today:
        raise StorePublishingError(f"근거 기준일이 미래입니다: {label}")
    return parsed.isoformat()


def _parse_verified_at(now: dt.datetime | None) -> str:
    value = now or dt.datetime.now(KST)
    if value.tzinfo is None or value.utcoffset() is None:
        raise StorePublishingError("verifiedAt 생성 시각에는 시간대가 필요합니다.")
    return value.astimezone(KST).replace(microsecond=0).isoformat()


def _assert_coordinates(
    expected: Mapping[str, str], actual: Mapping[str, str], label: str
) -> None:
    for field in ("latitude", "longitude"):
        if parse_coordinate(expected[field], field, label) != parse_coordinate(
            actual.get(field, ""), field, label
        ):
            raise StorePublishingError(f"좌표가 일치하지 않습니다: {label}, {field}")


def _assert_identity(
    expected: Mapping[str, str], actual: Mapping[str, str], *, label: str
) -> None:
    mismatches: list[str] = []
    for field in ("candidateId", "discoveryId", "sourcePlaceId"):
        if expected.get(field, "").strip() != actual.get(field, "").strip():
            mismatches.append(field)
    if expected.get("storeId", "").strip() != actual.get("storeId", "").strip():
        mismatches.append("storeId")
    for field in ("name", "address"):
        if not _same_text(expected[field], actual.get(field, "")):
            mismatches.append(field)
    _assert_coordinates(expected, actual, label)
    if mismatches:
        raise StorePublishingError(
            f"승인 식별 정보가 일치하지 않습니다: {label}, {mismatches}"
        )


def load_approval_manifest(path: Path) -> list[dict[str, Any]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise StorePublishingError(f"승인 명세를 읽을 수 없습니다: {path}") from error
    if not isinstance(payload, Mapping) or payload.get("version") != 1:
        raise StorePublishingError("승인 명세 version은 1이어야 합니다.")
    values = payload.get("approvals")
    if not isinstance(values, list) or len(values) != EXPECTED_APPROVALS:
        raise StorePublishingError(
            f"승인 allowlist는 정확히 {EXPECTED_APPROVALS}곳이어야 합니다."
        )

    approvals: list[dict[str, Any]] = []
    seen_review_ids: set[str] = set()
    seen_candidate_ids: set[str] = set()
    seen_store_ids: set[str] = set()
    for index, raw in enumerate(values, start=1):
        if not isinstance(raw, Mapping):
            raise StorePublishingError("승인 항목은 객체여야 합니다.")
        approval = {
            field: str(raw.get(field) or "").strip()
            for field in (
                "reviewItemId",
                "sourceGroup",
                "storeId",
                "candidateId",
                "discoveryId",
                "sourcePlaceId",
                "name",
                "address",
                "latitude",
                "longitude",
                "approvedStyle",
            )
        }
        approval["previousDecisionWithdrawn"] = (
            raw.get("previousDecisionWithdrawn") is True
        )
        approval["holdResolved"] = raw.get("holdResolved") is True
        label = approval["reviewItemId"] or f"approval {index}"
        if not approval["reviewItemId"].startswith("p6b_"):
            raise StorePublishingError(f"안정 reviewItemId가 필요합니다: {label}")
        if approval["sourceGroup"] not in {"pending", "hold"}:
            raise StorePublishingError(f"sourceGroup이 올바르지 않습니다: {label}")
        if not approval["candidateId"] or not approval["name"] or not approval["address"]:
            raise StorePublishingError(f"승인 식별 정보가 비었습니다: {label}")
        _assert_coordinates(approval, approval, label)
        if approval["approvedStyle"] not in ALLOWED_STYLES:
            raise StorePublishingError(f"승인 스타일이 올바르지 않습니다: {label}")
        if approval["sourceGroup"] == "pending":
            approval["storeId"] = _canonical_uuid(approval["storeId"], label)
            if approval["holdResolved"]:
                raise StorePublishingError(f"일반 후보에 hold 해소 표시가 있습니다: {label}")
        else:
            if approval["storeId"]:
                raise StorePublishingError(f"hold 후보는 사전 UUID를 가질 수 없습니다: {label}")
            if not approval["holdResolved"]:
                raise StorePublishingError(f"hold 해소 승인이 필요합니다: {label}")
        if approval["reviewItemId"] in seen_review_ids:
            raise StorePublishingError("승인 reviewItemId가 중복됐습니다.")
        if approval["candidateId"] in seen_candidate_ids:
            raise StorePublishingError("승인 candidateId가 중복됐습니다.")
        if approval["storeId"] and approval["storeId"] in seen_store_ids:
            raise StorePublishingError("승인 storeId가 중복됐습니다.")
        seen_review_ids.add(approval["reviewItemId"])
        seen_candidate_ids.add(approval["candidateId"])
        if approval["storeId"]:
            seen_store_ids.add(approval["storeId"])
        approvals.append(approval)

    groups = Counter(item["sourceGroup"] for item in approvals)
    if groups != {
        "pending": EXPECTED_PENDING_APPROVALS,
        "hold": EXPECTED_HOLD_APPROVALS,
    }:
        raise StorePublishingError(f"승인 그룹 집계가 다릅니다: {dict(groups)}")
    return approvals


def _state_counts(rows: Sequence[Mapping[str, str]]) -> tuple[Counter[str], int]:
    decisions = Counter(row.get("publishDecision", "").strip() for row in rows)
    active = sum(row.get("isActive", "").strip().lower() == "true" for row in rows)
    return decisions, active


def _verification_note(approval: Mapping[str, Any]) -> str:
    note = (
        "사용자 Phase 6B 명시적 승인. "
        f"안정 ID {approval['reviewItemId']}와 storeId·candidateId·매장명·주소·좌표를 검증함."
    )
    if approval["previousDecisionWithdrawn"]:
        note += " 사용자가 이전 제외 결정을 명시적으로 철회함."
    if approval["holdResolved"]:
        note += " 기존 hold 원인을 재검수해 해소 승인함."
    if approval["approvedStyle"] == "unclassified":
        note += " 게시 승인과 스타일 승인을 분리하며 스타일은 unclassified로 유지함."
    return note


def apply_25_store_expansion_approvals(
    publish_path: Path,
    expansion_path: Path,
    style_path: Path,
    staging_path: Path,
    hold_path: Path,
    kakao_path: Path,
    approval_path: Path,
    *,
    now: dt.datetime | None = None,
    uuid_factory: Callable[[], uuid.UUID] = uuid.uuid4,
) -> list[dict[str, str]]:
    if now is not None and (now.tzinfo is None or now.utcoffset() is None):
        raise StorePublishingError("now에는 시간대가 포함되어야 합니다.")
    protected_paths = (expansion_path, style_path, staging_path, hold_path, kakao_path)
    protected_hashes = {path: file_sha256(path) for path in protected_paths}
    today = (now.astimezone(KST).date() if now else dt.datetime.now(KST).date())
    approvals = load_approval_manifest(approval_path)

    publish_headers, publish_rows = read_csv_rows(publish_path, set(REVIEW_HEADERS))
    expansion_headers, expansion_rows = read_csv_rows(
        expansion_path, set(OUTPUT_HEADERS)
    )
    _, style_rows = read_csv_rows(style_path, STYLE_HEADERS)
    _, staging_rows = read_csv_rows(staging_path, STAGING_HEADERS)
    _, hold_rows = read_csv_rows(hold_path, HOLD_HEADERS)
    _, kakao_rows = read_csv_rows(kakao_path, KAKAO_HEADERS)
    if publish_headers != list(REVIEW_HEADERS):
        raise StorePublishingError("게시 검수표 컬럼 또는 순서가 다릅니다.")
    if expansion_headers != list(OUTPUT_HEADERS):
        raise StorePublishingError("Phase 6B 검수표 컬럼 또는 순서가 다릅니다.")

    expansion_by_id = _index_unique(expansion_rows, "reviewItemId", "Phase 6B 검수표")
    style_by_candidate = _index_unique(style_rows, "candidateId", "스타일 검수표")
    staging_by_candidate = _index_unique(staging_rows, "candidateId", "staging")
    hold_by_candidate = _index_unique(hold_rows, "candidateId", "hold report")
    kakao_by_place = _index_unique(kakao_rows, "sourcePlaceId", "Kakao 검수표")
    publish_by_candidate = _index_unique(publish_rows, "candidateId", "게시 검수표")

    review_ids = {approval["reviewItemId"] for approval in approvals}
    if not review_ids <= set(expansion_by_id):
        raise StorePublishingError("승인 안정 ID를 Phase 6B 검수표에서 찾을 수 없습니다.")
    approved_candidates = {approval["candidateId"] for approval in approvals}
    public_before = {
        row["candidateId"]: dict(row)
        for row in publish_rows
        if row["publishDecision"].strip() == "verified"
        and row["isActive"].strip().lower() == "true"
        and row["candidateId"] not in approved_candidates
    }
    unapproved_before = {
        row["candidateId"]: dict(row)
        for row in publish_rows
        if row["candidateId"] not in approved_candidates
    }

    pending_states = 0
    verified_states = 0
    hold_approval: dict[str, Any] | None = None
    for approval in approvals:
        item_id = approval["reviewItemId"]
        phase_row = expansion_by_id[item_id]
        _assert_identity(approval, phase_row, label=item_id)
        if phase_row["currentBurgerStyle"].strip() != approval["approvedStyle"]:
            raise StorePublishingError(f"승인 스타일이 Phase 6B 검수표와 다릅니다: {item_id}")
        source_as_of = _parse_date(phase_row["latestEvidenceAsOf"], item_id, today)
        approval["sourceAsOf"] = source_as_of

        if approval["sourceGroup"] == "pending":
            if phase_row["recommendedDecision"].strip() != "ready_for_user_approval":
                raise StorePublishingError(f"일반 후보가 승인 권고 상태가 아닙니다: {item_id}")
            publish_row = publish_by_candidate.get(approval["candidateId"])
            style_row = style_by_candidate.get(approval["candidateId"])
            staging_row = staging_by_candidate.get(approval["candidateId"])
            if not publish_row or not style_row or not staging_row:
                raise StorePublishingError(f"일반 후보의 입력 연결이 누락됐습니다: {item_id}")
            publish_identity = {
                **publish_row,
                "discoveryId": "",
                "sourcePlaceId": phase_row["sourcePlaceId"],
            }
            _assert_identity(approval, publish_identity, label=item_id)
            if not _same_text(approval["name"], staging_row["displayName"]):
                raise StorePublishingError(f"staging 매장명이 다릅니다: {item_id}")
            if not _same_text(approval["address"], staging_row["address"]):
                raise StorePublishingError(f"staging 주소가 다릅니다: {item_id}")
            _assert_coordinates(approval, staging_row, item_id)
            if style_row["storeId"].strip() != approval["storeId"]:
                raise StorePublishingError(f"스타일 storeId가 다릅니다: {item_id}")
            if not _same_text(approval["name"], style_row["name"]):
                raise StorePublishingError(f"스타일 매장명이 다릅니다: {item_id}")
            if style_row["proposedBurgerStyle"].strip() != approval["approvedStyle"]:
                raise StorePublishingError(f"스타일 검수 값이 다릅니다: {item_id}")
            state = (
                publish_row["publishDecision"].strip(),
                publish_row["isActive"].strip().lower(),
            )
            if state == ("pending", "false"):
                pending_states += 1
            elif state == ("verified", "true"):
                verified_states += 1
            else:
                raise StorePublishingError(f"일반 후보 게시 상태가 안전하지 않습니다: {item_id}")
        else:
            hold_approval = approval
            if phase_row["recommendedDecision"].strip() != "hold_resolved_ready_for_user_approval":
                raise StorePublishingError(f"hold 해소 권고 상태가 아닙니다: {item_id}")
            hold_row = hold_by_candidate.get(approval["candidateId"])
            kakao_row = kakao_by_place.get(approval["sourcePlaceId"])
            if not hold_row or not kakao_row:
                raise StorePublishingError(f"hold 원천 연결이 누락됐습니다: {item_id}")
            if hold_row["sourcePlaceId"].strip() != approval["sourcePlaceId"]:
                raise StorePublishingError(f"hold sourcePlaceId가 다릅니다: {item_id}")
            if not _same_text(hold_row["name"], approval["name"]):
                raise StorePublishingError(f"hold 매장명이 다릅니다: {item_id}")
            if kakao_row["discoveryId"].strip() != approval["discoveryId"]:
                raise StorePublishingError(f"hold discoveryId가 다릅니다: {item_id}")
            kakao_identity = {
                **kakao_row,
                "storeId": "",
                "candidateId": approval["candidateId"],
            }
            _assert_identity(approval, kakao_identity, label=item_id)
            existing_hold_row = publish_by_candidate.get(approval["candidateId"])
            if existing_hold_row is None:
                pending_states += 1
            elif (
                existing_hold_row["publishDecision"].strip(),
                existing_hold_row["isActive"].strip().lower(),
            ) == ("verified", "true"):
                verified_states += 1
            else:
                raise StorePublishingError(f"hold 게시 상태가 안전하지 않습니다: {item_id}")

    if pending_states == EXPECTED_APPROVALS and verified_states == 0:
        apply_changes = True
    elif verified_states == EXPECTED_APPROVALS and pending_states == 0:
        apply_changes = False
    else:
        raise StorePublishingError("Phase 6B 승인에 부분 반영 상태가 감지됐습니다.")

    output = [dict(row) for row in publish_rows]
    output_by_candidate = {row["candidateId"].strip(): row for row in output}
    verified_at = _parse_verified_at(now) if apply_changes else ""
    if apply_changes:
        assert hold_approval is not None
        hold_store_id = str(uuid_factory())
        if hold_store_id in {row["storeId"].strip() for row in output}:
            raise StorePublishingError("새 hold UUID가 기존 storeId와 중복됐습니다.")
        hold_phase = expansion_by_id[hold_approval["reviewItemId"]]
        hold_row = {
            "storeId": hold_store_id,
            "candidateId": hold_approval["candidateId"],
            "name": hold_approval["name"],
            "address": hold_approval["address"],
            "latitude": hold_approval["latitude"],
            "longitude": hold_approval["longitude"],
            "burgerStyle": hold_approval["approvedStyle"],
            "sourceType": "manual_review",
            "sourceAsOf": hold_approval["sourceAsOf"],
            "publishDecision": "verified",
            "isActive": "true",
            "verifiedAt": verified_at,
            "verificationNote": _verification_note(hold_approval),
        }
        if hold_phase["sourceGroup"] != "hold":
            raise StorePublishingError("hold 승인 원천 그룹이 바뀌었습니다.")
        output.append(hold_row)
        output_by_candidate[hold_approval["candidateId"]] = hold_row

        for approval in approvals:
            if approval["sourceGroup"] == "hold":
                continue
            row = output_by_candidate[approval["candidateId"]]
            row.update(
                {
                    "burgerStyle": approval["approvedStyle"],
                    "sourceAsOf": approval["sourceAsOf"],
                    "publishDecision": "verified",
                    "isActive": "true",
                    "verifiedAt": verified_at,
                    "verificationNote": _verification_note(approval),
                }
            )
    else:
        for approval in approvals:
            row = output_by_candidate[approval["candidateId"]]
            expected_store_id = approval["storeId"]
            if approval["sourceGroup"] == "hold":
                expected_store_id = _canonical_uuid(row["storeId"], approval["reviewItemId"])
            expected = {
                "storeId": expected_store_id,
                "burgerStyle": approval["approvedStyle"],
                "sourceAsOf": approval["sourceAsOf"],
                "publishDecision": "verified",
                "isActive": "true",
                "verificationNote": _verification_note(approval),
            }
            mismatches = [
                field for field, value in expected.items() if row.get(field, "").strip() != value
            ]
            if mismatches or not row["verifiedAt"].strip():
                raise StorePublishingError(
                    f"기존 승인 값이 승인 명세와 다릅니다: {approval['reviewItemId']}, {mismatches}"
                )

    decisions, active_count = _state_counts(output)
    if len(output) != EXPECTED_FINAL_ROWS:
        raise StorePublishingError(f"최종 게시 검수표가 {EXPECTED_FINAL_ROWS}행이 아닙니다.")
    if decisions != {"verified": EXPECTED_FINAL_PUBLIC, "pending": EXPECTED_FINAL_PENDING}:
        raise StorePublishingError(f"최종 게시 상태 집계가 다릅니다: {dict(decisions)}")
    if active_count != EXPECTED_FINAL_PUBLIC:
        raise StorePublishingError("최종 active 집계가 다릅니다.")
    store_ids = [_canonical_uuid(row["storeId"], row["candidateId"]) for row in output]
    if len(store_ids) != len(set(store_ids)):
        raise StorePublishingError("최종 게시 검수표 storeId가 중복됐습니다.")
    if any(output_by_candidate[key] != value for key, value in unapproved_before.items()):
        raise StorePublishingError("승인되지 않은 게시 검수표 행이 변경됐습니다.")
    if any(output_by_candidate[key] != value for key, value in public_before.items()):
        raise StorePublishingError("기존 공개 매장 행이 변경됐습니다.")

    if apply_changes:
        write_csv_rows(publish_path, REVIEW_HEADERS, output)
    if protected_hashes != {path: file_sha256(path) for path in protected_paths}:
        raise StorePublishingError("보호 입력 파일의 SHA-256이 변경됐습니다.")
    return output


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish-review", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--expansion-review", type=Path, default=DEFAULT_EXPANSION_PATH)
    parser.add_argument("--style-review", type=Path, default=DEFAULT_STYLE_PATH)
    parser.add_argument("--staging", type=Path, default=DEFAULT_STAGING_PATH)
    parser.add_argument("--hold-report", type=Path, default=DEFAULT_HOLD_PATH)
    parser.add_argument("--kakao-review", type=Path, default=DEFAULT_KAKAO_PATH)
    parser.add_argument("--approvals", type=Path, default=DEFAULT_APPROVAL_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows = apply_25_store_expansion_approvals(
            args.publish_review,
            args.expansion_review,
            args.style_review,
            args.staging,
            args.hold_report,
            args.kakao_review,
            args.approvals,
        )
        decisions, active = _state_counts(rows)
        print(
            json.dumps(
                {
                    "reviewRows": len(rows),
                    "verifiedRows": decisions["verified"],
                    "pendingRows": decisions["pending"],
                    "activeRows": active,
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
