#!/usr/bin/env python3
"""Collect review-only region evidence by approved store address; never publish it."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Mapping, Sequence
from urllib.parse import urlencode

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from audit_store_regions import (  # noqa: E402
    DEFAULT_PUBLISH_PATH,
    PUBLISH_FIELDS,
    RegionAuditError,
    normalize_address,
    read_csv_rows,
    select_approved_publish_rows,
    sha256_file,
)
from discover_kakao_burger_candidates import (  # noqa: E402
    DEFAULT_ENV_PATH,
    DiscoveryError,
    read_kakao_api_key,
    request_json,
)

API_URL = "https://dapi.kakao.com/v2/local/search/address.json"
DOCUMENTATION_URL = "https://developers.kakao.com/docs/ko/local/dev-guide"
ADDRESS_FIELDS = (
    "address_name",
    "region_1depth_name",
    "region_2depth_name",
    "region_3depth_name",
    "region_3depth_h_name",
    "b_code",
    "h_code",
)


def extract_evidence(query: str, response: Mapping[str, object]) -> dict[str, object]:
    """Preserve ambiguity and strip coordinates and unrecognized response fields."""
    meta = response.get("meta")
    documents = response.get("documents")
    if not isinstance(meta, dict) or not isinstance(documents, list):
        raise RegionAuditError("주소 API 응답에 유효한 meta/documents가 없습니다.")
    total = meta.get("total_count")
    pageable = meta.get("pageable_count")
    if (
        type(total) is not int
        or type(pageable) is not int
        or not 0 <= len(documents) <= pageable <= total
        or type(meta.get("is_end")) is not bool
        or (total == 0 and not meta["is_end"])
    ):
        raise RegionAuditError("주소 API 응답의 결과 수가 잘못되었습니다.")
    candidates = []
    for document in documents:
        if not isinstance(document, dict):
            raise RegionAuditError("주소 API 개별 결과가 객체가 아닙니다.")
        address = document.get("address")
        road = document.get("road_address")
        if address is not None and not isinstance(address, dict):
            raise RegionAuditError("주소 API 지역 필드 형식이 잘못되었습니다.")
        if road is not None and not isinstance(road, dict):
            raise RegionAuditError("주소 API 도로명 필드 형식이 잘못되었습니다.")
        address, road = address or {}, road or {}
        values = {field: address.get(field, "") for field in ADDRESS_FIELDS}
        values["road_address_name"] = road.get("address_name", "")
        if any(not isinstance(value, str) for value in values.values()):
            raise RegionAuditError("주소 API 지역 값이 문자열이 아닙니다.")
        issue_codes = []
        if not any(
            normalize_address(query) == normalize_address(value)
            for value in (values["address_name"], values["road_address_name"])
        ):
            issue_codes.append("ADDRESS_NOT_EXACT")
        if not all(values[field] for field in ADDRESS_FIELDS):
            issue_codes.append("REGION_EVIDENCE_INCOMPLETE")
        if any(
            not re.fullmatch(r"[0-9]{10}", values[field])
            for field in ("b_code", "h_code")
        ):
            issue_codes.append("REGION_CODE_INVALID")
        candidates.append({**values, "issueCodes": issue_codes})
    if total == 0:
        status = "no_result"
    elif total != 1 or len(candidates) != 1 or not meta["is_end"]:
        status = "ambiguous_or_partial"
    elif candidates[0]["issueCodes"]:
        status = "candidate_needs_review"
    else:
        status = "exact_address_region_evidence"
    return {
        "status": status,
        "totalCount": total,
        "returnedCount": len(candidates),
        "isEnd": meta["is_end"],
        "candidates": candidates,
        "manualReviewRequired": True,
        "storeExistenceVerified": False,
    }


def collect_evidence(
    publish_path: Path,
    output_dir: Path,
    api_key: str,
    *,
    max_requests: int = 25,
    timeout_seconds: float = 10,
    transport: Callable = request_json,
) -> dict[str, object]:
    if output_dir.exists():
        raise RegionAuditError("출력 디렉터리가 이미 존재합니다. 새 경로를 지정하세요.")
    if not api_key.strip():
        raise RegionAuditError("카카오 REST API 키가 없습니다.")
    if (
        not 1 <= max_requests <= 25
        or not math.isfinite(timeout_seconds)
        or timeout_seconds <= 0
    ):
        raise RegionAuditError("요청 수는 1~25, 제한 시간은 양수여야 합니다.")
    before_hash = sha256_file(publish_path)
    approved = select_approved_publish_rows(read_csv_rows(publish_path, PUBLISH_FIELDS))
    if len(approved) > max_requests:
        raise RegionAuditError("승인 대상이 최대 요청 수를 초과합니다. 일부만 조회하지 않았습니다.")
    # Claim a new output directory before issuing any network request.
    try:
        output_dir.mkdir(parents=True)
    except OSError:
        raise RegionAuditError("새 출력 디렉터리를 만들 수 없습니다.") from None
    rows = []
    aborted = False
    for row in approved:
        item = {
            "storeId": row["storeId"],
            "candidateId": row["candidateId"],
            "name": row["name"],
            "queryAddress": row["address"],
            "manualReviewRequired": True,
            "storeExistenceVerified": False,
        }
        if aborted:
            rows.append({**item, "status": "not_attempted_after_error"})
            continue
        url = (
            API_URL
            + "?"
            + urlencode(
                {
                    "query": row["address"],
                    "analyze_type": "exact",
                    "size": 10,
                }
            )
        )
        try:
            response = transport(
                url, {"Authorization": f"KakaoAK {api_key}"}, timeout_seconds
            )
            if not isinstance(response, dict):
                raise RegionAuditError("주소 API 응답이 객체가 아닙니다.")
            evidence = extract_evidence(row["address"], response)
        except (DiscoveryError, RegionAuditError, OSError, ValueError) as error:
            # Never serialize exceptions: headers, URLs or payloads may contain secrets.
            evidence = {
                "status": "request_or_response_error",
                "failureKind": "api_or_network"
                if isinstance(error, (DiscoveryError, OSError))
                else "invalid_response",
            }
            if isinstance(error, DiscoveryError):
                http_status = re.search(r"HTTP ([1-5][0-9]{2})", str(error))
                if http_status:
                    evidence["httpStatus"] = int(http_status[1])
            aborted = True
        rows.append(
            {**item, **evidence, "retrievedAt": datetime.now(timezone.utc).isoformat()}
        )
        # Retain completed evidence if a later request or process fails.
        with (output_dir / "region_evidence.jsonl").open(
            "a", encoding="utf-8"
        ) as stream:
            stream.write(json.dumps(rows[-1], ensure_ascii=False) + "\n")
    after_hash = sha256_file(publish_path)
    summary = {
        "source": {"path": str(publish_path.resolve()), "sha256": before_hash},
        "sourceUnchanged": before_hash == after_hash,
        "endpoint": API_URL,
        "documentation": DOCUMENTATION_URL,
        "queryOptions": {"analyze_type": "exact", "size": 10},
        "collectedAt": datetime.now(timezone.utc).isoformat(),
        "remoteSupabaseChecked": False,
        "publishReady": False,
        "approvedTargetRows": len(approved),
        "requestCount": sum(
            row["status"] != "not_attempted_after_error" for row in rows
        ),
        "statusCounts": dict(Counter(row["status"] for row in rows)),
        "automaticRetries": 0,
        "completed": not aborted and before_hash == after_hash,
    }
    # Also represent every unattempted UUID in the final artifact.
    with (output_dir / "region_evidence.jsonl").open("w", encoding="utf-8") as stream:
        for row in rows:
            stream.write(json.dumps(row, ensure_ascii=False) + "\n")
    (output_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return summary


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV_PATH)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--max-requests", type=int, default=25)
    args = parser.parse_args(argv)
    try:
        summary = collect_evidence(
            args.publish,
            args.output_dir,
            read_kakao_api_key(args.env_file),
            max_requests=args.max_requests,
        )
    except (DiscoveryError, RegionAuditError, OSError):
        print("지역 근거 수집을 시작/저장하지 못했습니다. 입력·설정·새 출력 경로를 확인하세요.", file=sys.stderr)
        return 2
    print(
        json.dumps(
            {
                key: summary[key]
                for key in ("completed", "requestCount", "statusCounts")
            },
            ensure_ascii=False,
        )
    )
    return 0 if summary["completed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
