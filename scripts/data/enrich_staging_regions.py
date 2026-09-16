#!/usr/bin/env python3
"""Add review-only legal region previews to an existing pending development asset."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

from audit_store_regions import normalize_address, sha256_file

BASE_FIELDS = {
    "id",
    "name",
    "address",
    "latitude",
    "longitude",
    "burgerStyle",
    "verificationStatus",
}


def enrich(items: list[dict], evidence: list[dict]) -> tuple[list[dict], list[dict]]:
    """Retain all stores/IDs/styles; unmatched evidence becomes an unknown region."""
    by_candidate = {}
    for row in evidence:
        candidate_id = row.get("candidateId")
        if (
            not isinstance(candidate_id, str)
            or not candidate_id
            or candidate_id in by_candidate
        ):
            raise ValueError("지역 근거 candidateId가 비었거나 중복되었습니다.")
        by_candidate[candidate_id] = row
    result, review, seen = [], [], set()
    for source in items:
        if (
            not isinstance(source, dict)
            or set(source) - BASE_FIELDS - {"region"}
            or BASE_FIELDS - set(source)
            or source["verificationStatus"] != "pending"
        ):
            raise ValueError("기존 pending 개발 asset만 지역 미리보기에 사용할 수 있습니다.")
        candidate_id = source["id"]
        if (
            not isinstance(candidate_id, str)
            or not candidate_id
            or candidate_id in seen
        ):
            raise ValueError("개발 asset ID가 비었거나 중복되었습니다.")
        seen.add(candidate_id)
        item = {key: value for key, value in source.items() if key != "region"}
        row = by_candidate.get(candidate_id)
        reason = "no_evidence"
        if row:
            reason = "evidence_requires_review"
            if row.get("status") == "exact_address_region_evidence":
                candidates = row.get("candidates", [])
                if row.get("name") != source["name"] or normalize_address(
                    row.get("queryAddress")
                ) != normalize_address(source["address"]):
                    reason = "asset_identity_or_address_differs"
                elif (
                    row.get("totalCount") != 1
                    or len(candidates) != 1
                    or candidates[0].get("issueCodes") != []
                ):
                    reason = "inconsistent_evidence"
                else:
                    candidate = candidates[0]
                    code = candidate.get("b_code", "")
                    names = [
                        candidate.get(field, "")
                        for field in (
                            "region_1depth_name",
                            "region_2depth_name",
                            "region_3depth_name",
                        )
                    ]
                    exact_address = any(
                        normalize_address(source["address"])
                        == normalize_address(candidate.get(field))
                        for field in ("address_name", "road_address_name")
                    )
                    if (
                        isinstance(code, str)
                        and re.fullmatch(r"[0-9]{8}00", code)
                        and code[5:8] != "000"
                        and exact_address
                        and all(
                            isinstance(name, str) and name.strip() for name in names
                        )
                    ):
                        item["region"] = {
                            "sidoCode": code[:2],
                            "sidoName": names[0],
                            "sigunguCode": code[:5],
                            "sigunguName": names[1],
                            "dongCode": code,
                            "dongName": names[2],
                        }
                        reason = "development_preview_only"
                    else:
                        reason = "unsupported_or_invalid_legal_region"
        result.append(item)
        review.append({"candidateId": candidate_id, "reason": reason})
    return result, review


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.output_dir.exists():
        parser.error("출력 디렉터리가 이미 존재합니다. 새 경로를 지정하세요.")
    try:
        items = json.loads(args.asset.read_text(encoding="utf-8-sig"))
        evidence = [
            json.loads(line)
            for line in args.evidence.read_text(encoding="utf-8").splitlines()
        ]
        result, review = enrich(items, evidence)
        receipt = {
            "inputAssetSha256": sha256_file(args.asset),
            "inputEvidenceSha256": sha256_file(args.evidence),
            "publishReady": False,
            "storeCount": len(result),
            "withRegionCount": sum("region" in row for row in result),
            "reasonCounts": dict(Counter(row["reason"] for row in review)),
            "rows": review,
        }
        args.output_dir.mkdir(parents=True, exist_ok=False)
        (args.output_dir / "staging_with_regions.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (args.output_dir / "receipt.json").write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except (OSError, ValueError, TypeError, AttributeError):
        parser.error("개발 asset 또는 지역 근거 형식/출력 경로가 올바르지 않습니다.")
    print(
        json.dumps(
            {
                key: receipt[key]
                for key in ("storeCount", "withRegionCount", "reasonCounts")
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
