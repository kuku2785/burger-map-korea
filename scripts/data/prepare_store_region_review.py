#!/usr/bin/env python3
"""Bind existing address evidence to a source review hash for offline review."""

from __future__ import annotations

import argparse
import json
import re
import sys
import uuid
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Mapping, Sequence

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from audit_store_regions import (  # noqa: E402
    PUBLISH_FIELDS,
    RegionAuditError,
    normalize_address,
    read_csv_rows,
    select_approved_publish_rows,
    sha256_file,
)


SUMMARY_NAME = "summary.json"
EVIDENCE_NAME = "region_evidence.jsonl"
REVIEW_NAME = "region_review.json"
SCHEMA_VERSION = 1


def _reject_duplicate_json_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise RegionAuditError(f"JSON 객체 키가 중복되었습니다: {key}")
        result[key] = value
    return result


def _loads_json(value: str, label: str) -> object:
    try:
        return json.loads(value, object_pairs_hook=_reject_duplicate_json_keys)
    except json.JSONDecodeError as error:
        raise RegionAuditError(f"JSON 형식이 잘못되었습니다: {label}") from error


def _read_json_object(path: Path) -> dict[str, object]:
    try:
        value = _loads_json(path.read_text(encoding="utf-8-sig"), str(path))
    except OSError as error:
        raise RegionAuditError(f"JSON을 읽을 수 없습니다: {path}") from error
    if not isinstance(value, dict):
        raise RegionAuditError(f"JSON 최상위 값이 객체가 아닙니다: {path}")
    return value


def _read_jsonl(path: Path) -> list[dict[str, object]]:
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except OSError as error:
        raise RegionAuditError(f"JSONL을 읽을 수 없습니다: {path}") from error
    if not lines or any(not line.strip() for line in lines):
        raise RegionAuditError(f"JSONL이 비었거나 빈 행을 포함합니다: {path}")
    rows: list[dict[str, object]] = []
    for line_number, line in enumerate(lines, 1):
        value = _loads_json(line, f"{path}, {line_number}행")
        if not isinstance(value, dict):
            raise RegionAuditError(f"JSONL 행이 객체가 아닙니다: {path}, {line_number}행")
        rows.append(value)
    return rows


def _require_timestamp(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise RegionAuditError(f"{label} 타임스탬프가 비었거나 문자열이 아닙니다.")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise RegionAuditError(f"{label} 타임스탬프 형식이 잘못되었습니다.") from error
    if parsed.tzinfo is None:
        raise RegionAuditError(f"{label} 타임스탬프에 시간대가 없습니다.")
    return value


def _canonical_uuid(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise RegionAuditError(f"{label} UUID가 비었거나 문자열이 아닙니다.")
    try:
        return str(uuid.UUID(value))
    except ValueError as error:
        raise RegionAuditError(f"{label} UUID 형식이 잘못되었습니다.") from error


def _require_exact_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise RegionAuditError(f"{label} 값이 비었거나 앞뒤 공백을 포함합니다.")
    return value


def _validate_collector_summary(
    summary: Mapping[str, object], publish_hash: str, approved_count: int
) -> str:
    source = summary.get("source")
    if not isinstance(source, dict) or source.get("sha256") != publish_hash:
        raise RegionAuditError("근거 summary의 source SHA-256이 현재 publish review와 다릅니다.")
    if (
        summary.get("sourceUnchanged") is not True
        or summary.get("completed") is not True
    ):
        raise RegionAuditError("완료되고 원본이 유지된 근거 수집 결과만 사용할 수 있습니다.")
    if summary.get("remoteSupabaseChecked") is not False:
        raise RegionAuditError("근거 summary의 remoteSupabaseChecked 경계가 잘못되었습니다.")
    if summary.get("publishReady") is not False:
        raise RegionAuditError("게시 준비 결과를 오프라인 검토 입력으로 사용할 수 없습니다.")
    if (
        type(summary.get("approvedTargetRows")) is not int
        or summary.get("approvedTargetRows") != approved_count
    ):
        raise RegionAuditError("근거 summary 대상 수가 현재 승인 대상과 다릅니다.")
    return _require_timestamp(summary.get("collectedAt"), "collectedAt")


def _index_evidence(
    rows: Sequence[Mapping[str, object]],
) -> tuple[dict[str, Mapping[str, object]], dict[str, Mapping[str, object]]]:
    by_store: dict[str, Mapping[str, object]] = {}
    by_candidate: dict[str, Mapping[str, object]] = {}
    for row_number, row in enumerate(rows, 1):
        store_id = _canonical_uuid(
            row.get("storeId"), f"evidence {row_number}행 storeId"
        )
        candidate_id = _require_exact_string(
            row.get("candidateId"), f"evidence {row_number}행 candidateId"
        )
        if store_id in by_store:
            raise RegionAuditError(f"evidence storeId가 정규화 후 중복되었습니다: {store_id}")
        if candidate_id in by_candidate:
            raise RegionAuditError(f"evidence candidateId가 중복되었습니다: {candidate_id}")
        by_store[store_id] = row
        by_candidate[candidate_id] = row
    return by_store, by_candidate


def _validate_identity_bindings(
    approved: Sequence[Mapping[str, str]],
    by_store: Mapping[str, Mapping[str, object]],
    by_candidate: Mapping[str, Mapping[str, object]],
) -> None:
    expected_store_ids = {row["storeId"] for row in approved}
    expected_candidate_ids = {row["candidateId"] for row in approved}
    if (
        set(by_store) != expected_store_ids
        or set(by_candidate) != expected_candidate_ids
    ):
        raise RegionAuditError("근거 JSONL 대상 집합에 누락 또는 고아 행이 있습니다.")
    for row in approved:
        evidence = by_store[row["storeId"]]
        if evidence is not by_candidate[row["candidateId"]]:
            raise RegionAuditError("근거 JSONL의 storeId와 candidateId 연결이 바뀌었습니다.")
        if evidence.get("name") != row["name"]:
            raise RegionAuditError(f"근거 이름이 publish review와 다릅니다: {row['storeId']}")
        if evidence.get("queryAddress") != row["address"]:
            raise RegionAuditError(f"근거 조회 주소가 publish review와 다릅니다: {row['storeId']}")
        if evidence.get("manualReviewRequired") is not True:
            raise RegionAuditError("근거 행의 manualReviewRequired 경계가 잘못되었습니다.")
        if evidence.get("storeExistenceVerified") is not False:
            raise RegionAuditError("지역 근거가 매장 존재 검증으로 표시되었습니다.")
        if (
            type(evidence.get("totalCount")) is not int
            or type(evidence.get("returnedCount")) is not int
            or type(evidence.get("isEnd")) is not bool
            or not isinstance(evidence.get("status"), str)
            or not isinstance(evidence.get("candidates"), list)
        ):
            raise RegionAuditError("근거 행의 결과 수/status/candidates 형식이 잘못되었습니다.")
        for candidate in evidence["candidates"]:
            if not isinstance(candidate, dict):
                raise RegionAuditError("근거 candidates 행이 객체가 아닙니다.")
            string_fields = (
                "address_name",
                "road_address_name",
                "region_1depth_name",
                "region_2depth_name",
                "region_3depth_name",
                "region_3depth_h_name",
                "b_code",
                "h_code",
            )
            if any(
                not isinstance(candidate.get(field), str) for field in string_fields
            ):
                raise RegionAuditError("근거 candidate 지역 필드가 문자열이 아닙니다.")
            issue_codes = candidate.get("issueCodes")
            if not isinstance(issue_codes, list) or any(
                not isinstance(code, str) for code in issue_codes
            ):
                raise RegionAuditError("근거 candidate issueCodes 형식이 잘못되었습니다.")


def _region_or_reasons(
    publish_row: Mapping[str, str], evidence: Mapping[str, object]
) -> tuple[dict[str, str] | None, list[str]]:
    reasons: list[str] = []
    if evidence.get("status") != "exact_address_region_evidence":
        reasons.append("EVIDENCE_STATUS_NOT_EXACT")
    candidates = evidence.get("candidates")
    if type(evidence.get("totalCount")) is not int or evidence.get("totalCount") != 1:
        reasons.append("EVIDENCE_COUNT_NOT_EXACTLY_ONE")
    if (
        type(evidence.get("returnedCount")) is not int
        or evidence.get("returnedCount") != 1
        or evidence.get("isEnd") is not True
    ):
        reasons.append("EVIDENCE_RESULTS_NOT_COMPLETE")
    if (
        not isinstance(candidates, list)
        or len(candidates) != 1
        or not isinstance(candidates[0], dict)
    ):
        reasons.append("EVIDENCE_CANDIDATE_MALFORMED")
        return None, reasons

    candidate = candidates[0]
    issue_codes = candidate.get("issueCodes")
    if issue_codes != []:
        reasons.append("EVIDENCE_ISSUES_PRESENT")
    addresses = (candidate.get("address_name"), candidate.get("road_address_name"))
    if not any(
        isinstance(address, str)
        and normalize_address(address) == normalize_address(publish_row["address"])
        for address in addresses
    ):
        reasons.append("EVIDENCE_ADDRESS_NOT_EXACT")

    code = candidate.get("b_code")
    if not isinstance(code, str) or re.fullmatch(r"[0-9]{8}00", code) is None:
        reasons.append("LEGAL_REGION_CODE_INVALID")
    elif code[5:8] == "000":
        reasons.append("LEGAL_REGION_PARENT_CODE")
    name_fields = (
        "region_1depth_name",
        "region_2depth_name",
        "region_3depth_name",
    )
    names = [candidate.get(field) for field in name_fields]
    if any(
        not isinstance(name, str) or not name.strip() or name != name.strip()
        for name in names
    ):
        reasons.append("LEGAL_REGION_NAME_INVALID")
    if reasons:
        return None, reasons
    assert isinstance(code, str)
    return (
        {
            "sidoCode": code[:2],
            "sidoName": names[0],
            "sigunguCode": code[:5],
            "sigunguName": names[1],
            "dongCode": code,
            "dongName": names[2],
        },
        [],
    )


def _base_record(
    publish_row: Mapping[str, str], evidence: Mapping[str, object]
) -> dict[str, object]:
    return {
        "storeId": publish_row["storeId"],
        "candidateId": publish_row["candidateId"],
        "preconditions": {
            "id": publish_row["storeId"],
            "name": publish_row["name"],
            "address": publish_row["address"],
            "verification_status": "verified",
            "is_active": True,
        },
        "evidence": {
            "status": evidence.get("status"),
            "publishSourceAsOf": (publish_row.get("sourceAsOf") or "").strip(),
            "retrievedAt": _require_timestamp(
                evidence.get("retrievedAt"),
                f"evidence {publish_row['storeId']} retrievedAt",
            ),
        },
        "offlineReviewOnly": True,
        "publishReady": False,
        "remoteSupabaseChecked": False,
        "manualReviewRequired": True,
    }


def build_review(
    approved: Sequence[Mapping[str, str]],
    evidence_by_store: Mapping[str, Mapping[str, object]],
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    review_candidates: list[dict[str, object]] = []
    excluded: list[dict[str, object]] = []
    for publish_row in approved:
        evidence = evidence_by_store[publish_row["storeId"]]
        record = _base_record(publish_row, evidence)
        region, reasons = _region_or_reasons(publish_row, evidence)
        if region is None:
            record["reasonCodes"] = reasons
            excluded.append(record)
        else:
            record["proposedUpdate"] = {"region": region}
            review_candidates.append(record)
    key = lambda row: str(row["storeId"])
    return sorted(review_candidates, key=key), sorted(excluded, key=key)


def prepare_review_package(
    publish_review_path: Path, evidence_dir: Path, output_dir: Path
) -> dict[str, object]:
    if output_dir.exists():
        raise RegionAuditError("출력 디렉터리가 이미 존재합니다. 새 경로를 지정하세요.")
    summary_path = evidence_dir / SUMMARY_NAME
    evidence_path = evidence_dir / EVIDENCE_NAME
    input_paths = {
        "publishReview": publish_review_path,
        "evidenceSummary": summary_path,
        "regionEvidence": evidence_path,
    }
    before_hashes = {key: sha256_file(path) for key, path in input_paths.items()}
    publish_rows = read_csv_rows(publish_review_path, PUBLISH_FIELDS)
    approved = select_approved_publish_rows(publish_rows)
    collector_summary = _read_json_object(summary_path)
    collected_at = _validate_collector_summary(
        collector_summary, before_hashes["publishReview"], len(approved)
    )
    evidence_rows = _read_jsonl(evidence_path)
    by_store, by_candidate = _index_evidence(evidence_rows)
    _validate_identity_bindings(approved, by_store, by_candidate)

    statuses = [row.get("status") for row in evidence_rows]
    if any(not isinstance(status, str) for status in statuses):
        raise RegionAuditError("근거 JSONL status가 문자열이 아닙니다.")
    status_counts = Counter(statuses)
    if collector_summary.get("statusCounts") != dict(status_counts):
        raise RegionAuditError("근거 summary 상태 집계가 JSONL과 다릅니다.")
    review_candidates, excluded = build_review(approved, by_store)
    after_hashes = {key: sha256_file(path) for key, path in input_paths.items()}
    if after_hashes != before_hashes:
        raise RegionAuditError("검토 패키지 준비 중 입력 파일이 변경되었습니다.")

    future_requirements = ["fresh current region", "fresh current updated_at"]
    package = {
        "schemaVersion": SCHEMA_VERSION,
        "packageStatus": "offline_region_review_candidates",
        "offlineReviewOnly": True,
        "publishReady": False,
        "remoteSupabaseChecked": False,
        "manualReviewRequired": True,
        "futureApplyRequires": future_requirements,
        "reviewCandidates": review_candidates,
        "excluded": excluded,
    }
    reason_counts = Counter(
        reason for row in excluded for reason in row.get("reasonCodes", [])
    )
    source = collector_summary["source"]
    assert isinstance(source, dict)
    summary: dict[str, object] = {
        "schemaVersion": SCHEMA_VERSION,
        "packageStatus": "offline_region_review_candidates",
        "sourceUnchanged": True,
        "offlineReviewOnly": True,
        "publishReady": False,
        "remoteSupabaseChecked": False,
        "manualReviewRequired": True,
        "futureApplyRequires": future_requirements,
        "inputs": {
            key: {
                "path": str(path.resolve()),
                "sha256": before_hashes[key],
                **(
                    {"rowCount": len(publish_rows)}
                    if key == "publishReview"
                    else {"rowCount": len(evidence_rows)}
                    if key == "regionEvidence"
                    else {}
                ),
            }
            for key, path in input_paths.items()
        },
        "evidenceSource": {
            "path": source.get("path"),
            "publishReviewSha256": source.get("sha256"),
            "collectedAt": collected_at,
            "endpoint": collector_summary.get("endpoint"),
            "documentation": collector_summary.get("documentation"),
            "queryOptions": collector_summary.get("queryOptions"),
            "automaticRetries": collector_summary.get("automaticRetries"),
            "retrievedAt": sorted(
                record["evidence"]["retrievedAt"]
                for record in review_candidates + excluded
            ),
        },
        "counts": {
            "publishRows": len(publish_rows),
            "approvedTargetRows": len(approved),
            "reviewCandidateRows": len(review_candidates),
            "excludedRows": len(excluded),
        },
        "excludedReasonCounts": dict(sorted(reason_counts.items())),
        "outputs": [REVIEW_NAME, SUMMARY_NAME],
    }
    try:
        output_dir.mkdir(parents=True, exist_ok=False)
        (output_dir / REVIEW_NAME).write_text(
            json.dumps(package, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (output_dir / SUMMARY_NAME).write_text(
            json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except OSError as error:
        raise RegionAuditError(f"검토 패키지 출력을 쓸 수 없습니다: {output_dir}") from error
    return summary


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish-review", type=Path, required=True)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        summary = prepare_review_package(
            args.publish_review, args.evidence_dir, args.output_dir
        )
    except RegionAuditError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2
    print(json.dumps(summary["counts"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
