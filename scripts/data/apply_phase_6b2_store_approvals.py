#!/usr/bin/env python3
"""Apply exactly two explicit Phase 6B-2 store approvals locally."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import sys
import uuid
from collections import Counter
from pathlib import Path
from typing import Any, Mapping, Sequence
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
    / "yongsan_burger_phase_6b2_approval_evidence.json"
)
DEFAULT_RESULT_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_burger_phase_6b2_approval_result.json"
)

EXPECTED_APPROVALS = 2
EXPECTED_INITIAL_ROWS = 25
EXPECTED_INITIAL_PUBLIC = 23
EXPECTED_INITIAL_PENDING = 2
EXPECTED_FINAL_ROWS = 26
EXPECTED_FINAL_PUBLIC = 25
EXPECTED_FINAL_PENDING = 1
MAX_ADDRESS_DISTANCE_METERS = 25.0
KST = ZoneInfo("Asia/Seoul")


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _same_text(left: str, right: str) -> bool:
    return normalize_store_text(left) == normalize_store_text(right)


def _normalize_address(value: str) -> str:
    return normalize_store_text(value).replace("서울특별시", "서울")


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


def _verified_at(now: dt.datetime | None) -> str:
    value = now or dt.datetime.now(KST)
    if value.tzinfo is None or value.utcoffset() is None:
        raise StorePublishingError("now에는 시간대가 포함되어야 합니다.")
    return value.astimezone(KST).replace(microsecond=0).isoformat()


def _distance_meters(
    latitude: float,
    longitude: float,
    reference_latitude: float,
    reference_longitude: float,
) -> float:
    earth_radius = 6_371_000.0
    lat1 = math.radians(latitude)
    lat2 = math.radians(reference_latitude)
    delta_latitude = math.radians(reference_latitude - latitude)
    delta_longitude = math.radians(reference_longitude - longitude)
    value = (
        math.sin(delta_latitude / 2) ** 2
        + math.cos(lat1)
        * math.cos(lat2)
        * math.sin(delta_longitude / 2) ** 2
    )
    return earth_radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))


def _write_json(path: Path, payload: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_name(f".{path.name}.tmp")
    try:
        temporary_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        temporary_path.replace(path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise StorePublishingError(f"승인 결과를 저장할 수 없습니다: {path}") from error


def load_phase_6b2_approval_manifest(
    path: Path, *, today: dt.date
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise StorePublishingError(f"승인 근거를 읽을 수 없습니다: {path}") from error
    if not isinstance(payload, Mapping) or payload.get("version") != 1:
        raise StorePublishingError("Phase 6B-2 승인 근거 version은 1이어야 합니다.")

    values = payload.get("approvals")
    if not isinstance(values, list) or len(values) != EXPECTED_APPROVALS:
        raise StorePublishingError("Phase 6B-2 승인은 정확히 2곳이어야 합니다.")
    exclusions = payload.get("excluded")
    if not isinstance(exclusions, list) or len(exclusions) != 1:
        raise StorePublishingError("명시적 승인 제외 후보가 정확히 1곳이어야 합니다.")

    approvals: list[dict[str, Any]] = []
    for raw in values:
        if not isinstance(raw, Mapping):
            raise StorePublishingError("승인 항목은 객체여야 합니다.")
        approval = {
            field: str(raw.get(field) or "").strip()
            for field in (
                "sourceGroup",
                "storeId",
                "candidateId",
                "discoveryId",
                "sourcePlaceId",
                "name",
                "previousAddress",
                "address",
                "latitude",
                "longitude",
                "addressReferenceLatitude",
                "addressReferenceLongitude",
                "approvedStyle",
                "sourceAsOf",
            )
        }
        label = approval["candidateId"] or "approval"
        if approval["sourceGroup"] not in {"pending", "hold"}:
            raise StorePublishingError(f"sourceGroup이 올바르지 않습니다: {label}")
        approval["storeId"] = _canonical_uuid(approval["storeId"], label)
        for field in ("candidateId", "sourcePlaceId", "name", "address"):
            if not approval[field]:
                raise StorePublishingError(f"승인 필드가 비었습니다: {label}, {field}")
        if approval["approvedStyle"] not in ALLOWED_STYLES:
            raise StorePublishingError(f"승인 스타일이 올바르지 않습니다: {label}")
        approval["sourceAsOf"] = _parse_date(approval["sourceAsOf"], label, today)
        latitude = parse_coordinate(approval["latitude"], "latitude", label)
        longitude = parse_coordinate(approval["longitude"], "longitude", label)
        reference_latitude = parse_coordinate(
            approval["addressReferenceLatitude"], "latitude", label
        )
        reference_longitude = parse_coordinate(
            approval["addressReferenceLongitude"], "longitude", label
        )
        distance = _distance_meters(
            latitude, longitude, reference_latitude, reference_longitude
        )
        if distance > MAX_ADDRESS_DISTANCE_METERS:
            raise StorePublishingError(
                f"승인 좌표가 주소 기준점과 너무 멉니다: {label}, {distance:.2f}m"
            )
        approval["addressDistanceMeters"] = round(distance, 2)
        evidence = raw.get("evidence")
        if not isinstance(evidence, list) or len(evidence) < 2:
            raise StorePublishingError(f"독립 근거가 2개 이상 필요합니다: {label}")
        if not all(
            isinstance(item, Mapping)
            and str(item.get("type") or "").strip()
            and str(item.get("title") or "").strip()
            and str(item.get("url") or "").strip().startswith("https://")
            for item in evidence
        ):
            raise StorePublishingError(f"근거 형식이 올바르지 않습니다: {label}")
        approvals.append(approval)

    if Counter(item["sourceGroup"] for item in approvals) != {
        "pending": 1,
        "hold": 1,
    }:
        raise StorePublishingError("승인은 pending 1곳과 hold 1곳이어야 합니다.")
    for field in ("storeId", "candidateId", "sourcePlaceId"):
        values_for_field = [item[field] for item in approvals]
        if len(values_for_field) != len(set(values_for_field)):
            raise StorePublishingError(f"승인 {field}가 중복됐습니다.")

    exclusion_raw = exclusions[0]
    if not isinstance(exclusion_raw, Mapping):
        raise StorePublishingError("승인 제외 항목은 객체여야 합니다.")
    exclusion = {
        field: str(exclusion_raw.get(field) or "").strip()
        for field in ("candidateId", "sourcePlaceId", "name")
    }
    if not all(exclusion.values()):
        raise StorePublishingError("승인 제외 후보의 안정 식별자가 비었습니다.")
    if exclusion["candidateId"] in {item["candidateId"] for item in approvals}:
        raise StorePublishingError("승인 제외 후보가 승인 목록에도 포함됐습니다.")
    return approvals, exclusion


def _public_source_place_ids(
    public_candidate_ids: set[str],
    expansion_rows: Sequence[Mapping[str, str]],
    kakao_rows: Sequence[Mapping[str, str]],
) -> set[str]:
    values = {
        row.get("sourcePlaceId", "").strip()
        for row in expansion_rows
        if row.get("candidateId", "").strip() in public_candidate_ids
    }
    for row in kakao_rows:
        candidate_id = row.get("matchedCandidateId", "").strip()
        place_id = row.get("sourcePlaceId", "").strip()
        if candidate_id in public_candidate_ids:
            values.add(place_id)
        if f"kakao_{place_id}" in public_candidate_ids:
            values.add(place_id)
    return {value for value in values if value}


def apply_phase_6b2_store_approvals(
    publish_path: Path,
    expansion_path: Path,
    hold_path: Path,
    kakao_path: Path,
    approval_path: Path,
    result_path: Path,
    *,
    now: dt.datetime | None = None,
) -> list[dict[str, str]]:
    verified_at = _verified_at(now)
    today = dt.datetime.fromisoformat(verified_at).date()
    protected_paths = (expansion_path, hold_path, kakao_path, approval_path)
    protected_hashes = {path: file_sha256(path) for path in protected_paths}
    approvals, exclusion = load_phase_6b2_approval_manifest(approval_path, today=today)

    publish_headers, publish_rows = read_csv_rows(publish_path, set(REVIEW_HEADERS))
    expansion_headers, expansion_rows = read_csv_rows(
        expansion_path, set(OUTPUT_HEADERS)
    )
    _, hold_rows = read_csv_rows(
        hold_path,
        {"candidateId", "sourcePlaceId", "name", "stagingStatus"},
    )
    _, kakao_rows = read_csv_rows(
        kakao_path,
        {
            "discoveryId",
            "sourcePlaceId",
            "name",
            "address",
            "latitude",
            "longitude",
            "matchedCandidateId",
        },
    )
    if publish_headers != list(REVIEW_HEADERS):
        raise StorePublishingError("게시 검수표 컬럼 또는 순서가 다릅니다.")
    if expansion_headers != list(OUTPUT_HEADERS):
        raise StorePublishingError("Phase 6B 검수표 컬럼 또는 순서가 다릅니다.")

    if len(publish_rows) not in {EXPECTED_INITIAL_ROWS, EXPECTED_FINAL_ROWS}:
        raise StorePublishingError("게시 검수표 행 수가 Phase 6B-2 상태가 아닙니다.")
    publish_by_candidate = {row["candidateId"].strip(): row for row in publish_rows}
    if len(publish_by_candidate) != len(publish_rows):
        raise StorePublishingError("게시 검수표 candidateId가 중복됐습니다.")
    expansion_by_candidate = {
        row["candidateId"].strip(): row for row in expansion_rows
    }
    hold_by_candidate = {row["candidateId"].strip(): row for row in hold_rows}
    kakao_by_place = {row["sourcePlaceId"].strip(): row for row in kakao_rows}

    excluded_row = publish_by_candidate.get(exclusion["candidateId"])
    excluded_phase = expansion_by_candidate.get(exclusion["candidateId"])
    if (
        excluded_row is None
        or excluded_phase is None
        or excluded_phase["sourcePlaceId"].strip() != exclusion["sourcePlaceId"]
        or not _same_text(excluded_row["name"], exclusion["name"])
        or excluded_row["publishDecision"].strip() != "pending"
        or excluded_row["isActive"].strip().lower() != "false"
    ):
        raise StorePublishingError("승인 제외 후보가 pending+inactive 상태가 아닙니다.")

    approval_candidates = {item["candidateId"] for item in approvals}
    existing_public = [
        row
        for row in publish_rows
        if row["publishDecision"].strip() == "verified"
        and row["isActive"].strip().lower() == "true"
        and row["candidateId"].strip() not in approval_candidates
    ]
    if len(existing_public) != EXPECTED_INITIAL_PUBLIC:
        raise StorePublishingError("기존 공개 매장이 정확히 23곳이 아닙니다.")
    public_candidate_ids = {row["candidateId"].strip() for row in existing_public}
    public_store_ids = {row["storeId"].strip() for row in existing_public}
    public_name_addresses = {
        (normalize_store_text(row["name"]), _normalize_address(row["address"]))
        for row in existing_public
    }
    public_place_ids = _public_source_place_ids(
        public_candidate_ids, expansion_rows, kakao_rows
    )

    states: list[str] = []
    for approval in approvals:
        candidate_id = approval["candidateId"]
        label = candidate_id
        if approval["storeId"] in public_store_ids:
            raise StorePublishingError(f"승인 UUID가 기존 공개 매장과 중복됐습니다: {label}")
        if (
            normalize_store_text(approval["name"]),
            _normalize_address(approval["address"]),
        ) in public_name_addresses:
            raise StorePublishingError(f"승인 매장명+주소가 기존 공개 매장과 중복됐습니다: {label}")
        if approval["sourcePlaceId"] in public_place_ids:
            raise StorePublishingError(f"승인 sourcePlaceId가 기존 공개 매장과 중복됐습니다: {label}")

        current = publish_by_candidate.get(candidate_id)
        if approval["sourceGroup"] == "pending":
            phase = expansion_by_candidate.get(candidate_id)
            if current is None or phase is None:
                raise StorePublishingError(f"pending 승인 원천이 없습니다: {label}")
            if current["storeId"].strip() != approval["storeId"]:
                raise StorePublishingError(f"pending storeId가 다릅니다: {label}")
            if phase["sourcePlaceId"].strip() != approval["sourcePlaceId"]:
                raise StorePublishingError(f"pending sourcePlaceId가 다릅니다: {label}")
            if not _same_text(current["name"], approval["name"]):
                raise StorePublishingError(f"pending 매장명이 다릅니다: {label}")
            current_state = (
                current["publishDecision"].strip(),
                current["isActive"].strip().lower(),
            )
            expected_address = (
                approval["address"]
                if current_state == ("verified", "true")
                else approval["previousAddress"]
            )
            if _normalize_address(current["address"]) != _normalize_address(
                expected_address
            ):
                raise StorePublishingError(f"pending 이전 주소가 다릅니다: {label}")
            if parse_coordinate(current["latitude"], "latitude", label) != parse_coordinate(
                approval["latitude"], "latitude", label
            ) or parse_coordinate(
                current["longitude"], "longitude", label
            ) != parse_coordinate(approval["longitude"], "longitude", label):
                raise StorePublishingError(f"pending 좌표가 승인 근거와 다릅니다: {label}")
        else:
            hold = hold_by_candidate.get(candidate_id)
            kakao = kakao_by_place.get(approval["sourcePlaceId"])
            if hold is None or kakao is None:
                raise StorePublishingError(f"hold 승인 원천이 없습니다: {label}")
            if hold["sourcePlaceId"].strip() != approval["sourcePlaceId"]:
                raise StorePublishingError(f"hold sourcePlaceId가 다릅니다: {label}")
            if kakao["discoveryId"].strip() != approval["discoveryId"]:
                raise StorePublishingError(f"hold discoveryId가 다릅니다: {label}")
            if not _same_text(hold["name"], approval["name"]):
                raise StorePublishingError(f"hold 매장명이 다릅니다: {label}")
            if not _normalize_address(approval["address"]).startswith(
                _normalize_address(kakao["address"])
            ):
                raise StorePublishingError(f"hold 현재 주소가 원천 주소와 다릅니다: {label}")
            if parse_coordinate(kakao["latitude"], "latitude", label) != parse_coordinate(
                approval["latitude"], "latitude", label
            ) or parse_coordinate(
                kakao["longitude"], "longitude", label
            ) != parse_coordinate(approval["longitude"], "longitude", label):
                raise StorePublishingError(f"hold 현재 좌표가 원천 좌표와 다릅니다: {label}")

        if current is None:
            states.append("pending")
        elif (
            current["publishDecision"].strip(),
            current["isActive"].strip().lower(),
        ) == ("pending", "false"):
            states.append("pending")
        elif (
            current["publishDecision"].strip(),
            current["isActive"].strip().lower(),
        ) == ("verified", "true"):
            states.append("verified")
        else:
            raise StorePublishingError(f"승인 후보 상태가 안전하지 않습니다: {label}")

    if states == ["pending", "pending"] or sorted(states) == ["pending", "pending"]:
        apply_changes = True
    elif states == ["verified", "verified"] or sorted(states) == ["verified", "verified"]:
        apply_changes = False
    else:
        raise StorePublishingError("Phase 6B-2 승인이 부분 반영된 상태입니다.")

    output = [dict(row) for row in publish_rows]
    output_by_candidate = {row["candidateId"].strip(): row for row in output}
    if apply_changes:
        for approval in approvals:
            row = {
                "storeId": approval["storeId"],
                "candidateId": approval["candidateId"],
                "name": approval["name"],
                "address": approval["address"],
                "latitude": approval["latitude"],
                "longitude": approval["longitude"],
                "burgerStyle": approval["approvedStyle"],
                "sourceType": (
                    output_by_candidate[approval["candidateId"]]["sourceType"]
                    if approval["sourceGroup"] == "pending"
                    else "manual_review"
                ),
                "sourceAsOf": approval["sourceAsOf"],
                "publishDecision": "verified",
                "isActive": "true",
                "verifiedAt": verified_at,
                "verificationNote": (
                    "사용자 Phase 6B-2 명시적 승인. 현재 영업, 매장명, 주소와 "
                    "주소 기준 좌표 일치를 재검증함. 게시 승인과 스타일 검수는 분리함."
                ),
            }
            existing = output_by_candidate.get(approval["candidateId"])
            if existing is None:
                output.append(row)
            else:
                existing.update(row)
            output_by_candidate[approval["candidateId"]] = row if existing is None else existing
    else:
        for approval in approvals:
            row = output_by_candidate[approval["candidateId"]]
            expected = {
                "storeId": approval["storeId"],
                "name": approval["name"],
                "address": approval["address"],
                "latitude": approval["latitude"],
                "longitude": approval["longitude"],
                "burgerStyle": approval["approvedStyle"],
                "sourceAsOf": approval["sourceAsOf"],
                "publishDecision": "verified",
                "isActive": "true",
            }
            if any(row.get(field, "").strip() != value for field, value in expected.items()):
                raise StorePublishingError(
                    f"기존 승인 값이 승인 근거와 다릅니다: {approval['candidateId']}"
                )
            if not row["verifiedAt"].strip():
                raise StorePublishingError("기존 승인 verifiedAt이 비었습니다.")

    decisions = Counter(row["publishDecision"].strip() for row in output)
    active_count = sum(row["isActive"].strip().lower() == "true" for row in output)
    if len(output) != EXPECTED_FINAL_ROWS:
        raise StorePublishingError("최종 게시 검수표가 26행이 아닙니다.")
    if decisions != {"verified": EXPECTED_FINAL_PUBLIC, "pending": EXPECTED_FINAL_PENDING}:
        raise StorePublishingError(f"최종 게시 상태 집계가 다릅니다: {dict(decisions)}")
    if active_count != EXPECTED_FINAL_PUBLIC:
        raise StorePublishingError("최종 active 매장이 25곳이 아닙니다.")
    ids = [_canonical_uuid(row["storeId"], row["candidateId"]) for row in output]
    if len(ids) != len(set(ids)):
        raise StorePublishingError("최종 storeId가 중복됐습니다.")
    if output_by_candidate[exclusion["candidateId"]] != excluded_row:
        raise StorePublishingError("승인 제외 후보가 변경됐습니다.")

    for approval in approvals:
        historical = approval["previousAddress"]
        if approval["sourceGroup"] == "hold" and historical:
            current_row = output_by_candidate[approval["candidateId"]]
            if _normalize_address(historical) in _normalize_address(
                current_row["address"]
            ):
                raise StorePublishingError("과거 hold 주소가 현재 공개 주소에 남았습니다.")

    if apply_changes:
        write_csv_rows(publish_path, REVIEW_HEADERS, output)
    result = {
        "version": 1,
        "applied": apply_changes,
        "verifiedActive": EXPECTED_FINAL_PUBLIC,
        "pendingInactive": EXPECTED_FINAL_PENDING,
        "approved": [
            {
                "candidateId": item["candidateId"],
                "sourcePlaceId": item["sourcePlaceId"],
                "storeId": item["storeId"],
                "name": item["name"],
                "address": item["address"],
                "latitude": item["latitude"],
                "longitude": item["longitude"],
                "addressDistanceMeters": item["addressDistanceMeters"],
            }
            for item in approvals
        ],
        "excludedCandidateId": exclusion["candidateId"],
        "publishReviewSha256": file_sha256(publish_path),
    }
    _write_json(result_path, result)
    if protected_hashes != {path: file_sha256(path) for path in protected_paths}:
        raise StorePublishingError("보호 입력 파일의 SHA-256이 변경됐습니다.")
    return output


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish-review", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--expansion-review", type=Path, default=DEFAULT_EXPANSION_PATH)
    parser.add_argument("--hold-report", type=Path, default=DEFAULT_HOLD_PATH)
    parser.add_argument("--kakao-review", type=Path, default=DEFAULT_KAKAO_PATH)
    parser.add_argument("--approvals", type=Path, default=DEFAULT_APPROVAL_PATH)
    parser.add_argument("--result", type=Path, default=DEFAULT_RESULT_PATH)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows = apply_phase_6b2_store_approvals(
            args.publish_review,
            args.expansion_review,
            args.hold_report,
            args.kakao_review,
            args.approvals,
            args.result,
        )
        print(
            json.dumps(
                {
                    "reviewRows": len(rows),
                    "verifiedActive": sum(
                        row["publishDecision"] == "verified"
                        and row["isActive"] == "true"
                        for row in rows
                    ),
                    "pendingInactive": sum(
                        row["publishDecision"] == "pending"
                        and row["isActive"] == "false"
                        for row in rows
                    ),
                    "outputPath": str(args.publish_review.resolve()),
                    "resultPath": str(args.result.resolve()),
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
