#!/usr/bin/env python3
"""Audit offline region evidence for approved stores without changing source data."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import unicodedata
import uuid
from pathlib import Path
from typing import Mapping, Sequence

from store_publishing_common import ALLOWED_REVIEW_DECISIONS


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PUBLISH_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_store_publish_review.csv"
)
DEFAULT_STAGING_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_stores_staging.csv"
)
DEFAULT_RAW_PATH = PROJECT_ROOT / "data" / "raw" / "seoul_commercial_stores.csv"
DEFAULT_LOCAL_SNAPSHOT_PATH = (
    PROJECT_ROOT / "data" / "review" / "seoul_verified_active.csv"
)
DEFAULT_DEV_ASSET_PATH = (
    PROJECT_ROOT / "assets" / "dev" / "yongsan_burger_stores_staging.json"
)

PUBLISH_FIELDS = {
    "storeId",
    "candidateId",
    "name",
    "address",
    "burgerStyle",
    "publishDecision",
    "isActive",
}
STAGING_FIELDS = {"candidateId", "sourceStoreId"}
LOCAL_FIELDS = {"id", "name", "address", "burger_style"}
LOCAL_VERIFICATION_FIELDS = {"verification_status", "is_active"}
RAW_FIELDS = {
    "상가업소번호",
    "상호명",
    "시도코드",
    "시도명",
    "시군구코드",
    "시군구명",
    "행정동코드",
    "행정동명",
    "법정동코드",
    "법정동명",
    "도로명주소",
}
REGION_FIELDS = (
    "시도코드",
    "시도명",
    "시군구코드",
    "시군구명",
    "행정동코드",
    "행정동명",
    "법정동코드",
    "법정동명",
)
AUDIT_HEADERS = (
    "storeId",
    "candidateId",
    "name",
    "approvedAddress",
    "burgerStyle",
    "sourceAsOf",
    "sourceStoreId",
    "sourceStoreName",
    "sourceRoadAddress",
    "sidoCode",
    "sidoName",
    "sigunguCode",
    "sigunguName",
    "administrativeDongCode",
    "administrativeDongName",
    "legalDongCode",
    "legalDongName",
    "sourceLinked",
    "sourceAddressMatches",
    "regionComplete",
    "manualReviewRequired",
    "issueCodes",
)


class RegionAuditError(ValueError):
    """Raised when an input cannot be audited without an ambiguous join."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise RegionAuditError(f"입력 파일을 읽을 수 없습니다: {path}") from error
    return digest.hexdigest()


def _validate_csv_headers(
    path: Path, headers: Sequence[str] | None, required_fields: set[str]
) -> tuple[str, ...]:
    if not headers:
        raise RegionAuditError(f"CSV 헤더가 없습니다: {path}")
    if any(not isinstance(header, str) or not header.strip() for header in headers):
        raise RegionAuditError(f"CSV 헤더에 빈 열 이름이 있습니다: {path}")
    if any(header != header.strip() for header in headers):
        raise RegionAuditError(f"CSV 헤더 앞뒤에 공백이 있습니다: {path}")
    duplicates = sorted({header for header in headers if headers.count(header) > 1})
    if duplicates:
        raise RegionAuditError(f"CSV 헤더가 중복되었습니다: {path}, {duplicates}")
    missing = sorted(required_fields - set(headers))
    if missing:
        raise RegionAuditError(f"필수 CSV 열이 없습니다: {path}, {missing}")
    return tuple(headers)


def _validate_csv_row(
    path: Path, headers: Sequence[str], row_number: int, row: Mapping[object, object]
) -> None:
    if None in row:
        raise RegionAuditError(f"CSV 행에 헤더보다 많은 값이 있습니다: {path}, {row_number}행")
    missing_values = [header for header in headers if row.get(header) is None]
    if missing_values:
        raise RegionAuditError(f"CSV 행에 헤더보다 적은 값이 있습니다: {path}, {row_number}행")


def _read_csv_rows_and_headers(
    path: Path, required_fields: set[str]
) -> tuple[tuple[str, ...], list[dict[str, str]]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as source:
            reader = csv.DictReader(source, strict=True)
            headers = _validate_csv_headers(path, reader.fieldnames, required_fields)
            rows: list[dict[str, str]] = []
            for row_number, row in enumerate(reader, 2):
                _validate_csv_row(path, headers, row_number, row)
                rows.append(dict(row))
            return headers, rows
    except csv.Error as error:
        raise RegionAuditError(f"CSV 형식이 잘못되었습니다: {path}, {error}") from error
    except OSError as error:
        raise RegionAuditError(f"입력 CSV를 읽을 수 없습니다: {path}") from error


def read_csv_rows(path: Path, required_fields: set[str]) -> list[dict[str, str]]:
    """Read a validated CSV while preserving the established rows-only API."""
    return _read_csv_rows_and_headers(path, required_fields)[1]


def _require_unique(
    rows: Sequence[Mapping[str, object]], field: str, label: str
) -> dict[str, Mapping[str, object]]:
    indexed: dict[str, Mapping[str, object]] = {}
    for row_number, row in enumerate(rows, 2):
        raw_value = row.get(field)
        if not isinstance(raw_value, str) or not raw_value.strip():
            raise RegionAuditError(f"{label} {field}가 비었습니다: {row_number}행")
        value = raw_value.strip()
        if value in indexed:
            raise RegionAuditError(f"{label} {field}가 중복되었습니다: {value}")
        indexed[value] = row
    return indexed


def select_approved_publish_rows(
    rows: Sequence[Mapping[str, str]],
) -> list[dict[str, str]]:
    _require_unique(rows, "candidateId", "publish")
    store_ids: set[str] = set()
    selected: list[dict[str, str]] = []
    for row_number, source_row in enumerate(rows, 2):
        row = {key: (value or "").strip() for key, value in source_row.items()}
        try:
            parsed_id = uuid.UUID(row["storeId"])
        except (KeyError, ValueError, AttributeError):
            raise RegionAuditError(
                f"publish storeId가 UUID가 아닙니다: {row_number}행"
            ) from None
        if str(parsed_id) != row["storeId"].lower():
            raise RegionAuditError(
                f"publish storeId가 표준 UUID 형식이 아닙니다: {row['storeId']}"
            )
        canonical_id = str(parsed_id)
        if canonical_id in store_ids:
            raise RegionAuditError(
                f"publish storeId가 대소문자 구분 없이 중복되었습니다: {canonical_id}"
            )
        store_ids.add(canonical_id)
        row["storeId"] = canonical_id
        if row.get("publishDecision") not in ALLOWED_REVIEW_DECISIONS:
            raise RegionAuditError(f"publish publishDecision 값이 잘못되었습니다: {row_number}행")
        if row.get("isActive") not in {"true", "false"}:
            raise RegionAuditError(f"publish isActive 값이 잘못되었습니다: {row_number}행")
        if not all(row.get(field) for field in ("name", "address")):
            raise RegionAuditError(f"publish 필수 값이 비었습니다: {row_number}행")
        if row.get("publishDecision") == "verified" and row["isActive"] == "true":
            selected.append(row)
    return selected


def normalize_address(value: str | None) -> str:
    """Normalize only whitespace and the Seoul/Seoul Special City prefix."""
    normalized = unicodedata.normalize("NFKC", value or "")
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return re.sub(r"^서울특별시(?=\s)", "서울", normalized)


def scan_raw_rows(
    path: Path, referenced_ids: set[str]
) -> tuple[dict[str, dict[str, str]], int]:
    matches: dict[str, dict[str, str]] = {}
    count = 0
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as source:
            reader = csv.DictReader(source, strict=True)
            headers = _validate_csv_headers(path, reader.fieldnames, RAW_FIELDS)
            for row_number, row in enumerate(reader, 2):
                _validate_csv_row(path, headers, row_number, row)
                count += 1
                source_id = (row.get("상가업소번호") or "").strip()
                if source_id not in referenced_ids:
                    continue
                if source_id in matches:
                    raise RegionAuditError(f"참조된 raw 상가업소번호가 중복되었습니다: {source_id}")
                matches[source_id] = {
                    field: (row.get(field) or "").strip() for field in RAW_FIELDS
                }
    except csv.Error as error:
        raise RegionAuditError(f"raw CSV 형식이 잘못되었습니다: {path}, {error}") from error
    except OSError as error:
        raise RegionAuditError(f"raw CSV를 읽을 수 없습니다: {path}") from error
    return matches, count


def _compare_local_snapshot(
    approved: Sequence[Mapping[str, str]], local_rows: Sequence[Mapping[str, str]]
) -> dict[str, object]:
    approved_by_id = {row["storeId"]: row for row in approved}
    local_by_id: dict[str, Mapping[str, str]] = {}
    for row_number, row in enumerate(local_rows, 2):
        raw_id = (row.get("id") or "").strip()
        try:
            parsed_id = uuid.UUID(raw_id)
        except (ValueError, AttributeError):
            raise RegionAuditError(
                f"local snapshot id가 UUID가 아닙니다: {row_number}행"
            ) from None
        if str(parsed_id) != raw_id.lower():
            raise RegionAuditError(f"local snapshot id가 표준 UUID 형식이 아닙니다: {raw_id}")
        canonical_id = str(parsed_id)
        if canonical_id in local_by_id:
            raise RegionAuditError(
                f"local snapshot id가 대소문자 구분 없이 중복되었습니다: {canonical_id}"
            )
        local_by_id[canonical_id] = row
    differences: list[dict[str, object]] = []
    field_map = {"name": "name", "address": "address", "burgerStyle": "burger_style"}
    for store_id in sorted(set(approved_by_id) & set(local_by_id)):
        changed = {
            approved_field: {
                "approved": approved_by_id[store_id][approved_field],
                "localSnapshot": (local_by_id[store_id].get(local_field) or "").strip(),
            }
            for approved_field, local_field in field_map.items()
            if approved_by_id[store_id][approved_field]
            != (local_by_id[store_id].get(local_field) or "").strip()
        }
        if changed:
            differences.append({"storeId": store_id, "fields": changed})
    return {
        "idOnlyInApprovedTarget": sorted(set(approved_by_id) - set(local_by_id)),
        "idOnlyInLocalSnapshot": sorted(set(local_by_id) - set(approved_by_id)),
        "fieldDifferences": differences,
    }


def build_audit_rows(
    publish_rows: Sequence[Mapping[str, str]],
    staging_rows: Sequence[Mapping[str, str]],
    raw_by_id: Mapping[str, Mapping[str, str]],
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    approved = select_approved_publish_rows(publish_rows)
    staging_by_candidate = _require_unique(staging_rows, "candidateId", "staging")
    referenced: dict[str, str] = {}
    for row in approved:
        staging = staging_by_candidate.get(row["candidateId"])
        source_id = (staging.get("sourceStoreId") or "").strip() if staging else ""
        if source_id and source_id in referenced:
            raise RegionAuditError(
                "승인 대상이 같은 raw 상가업소번호를 참조합니다: "
                f"{source_id} ({referenced[source_id]}, {row['candidateId']})"
            )
        if source_id:
            referenced[source_id] = row["candidateId"]

    output: list[dict[str, str]] = []
    region_output_fields = {
        "시도코드": "sidoCode",
        "시도명": "sidoName",
        "시군구코드": "sigunguCode",
        "시군구명": "sigunguName",
        "행정동코드": "administrativeDongCode",
        "행정동명": "administrativeDongName",
        "법정동코드": "legalDongCode",
        "법정동명": "legalDongName",
    }
    for row in approved:
        staging = staging_by_candidate.get(row["candidateId"])
        source_id = (staging.get("sourceStoreId") or "").strip() if staging else ""
        raw = raw_by_id.get(source_id) if source_id else None
        issues: list[str] = []
        if not row["burgerStyle"]:
            issues.append("APPROVED_BURGER_STYLE_EMPTY")
        if staging is None:
            issues.append("STAGING_CANDIDATE_NOT_FOUND")
        elif not source_id:
            issues.append("SOURCE_STORE_ID_MISSING")
        elif raw is None:
            issues.append("RAW_SOURCE_NOT_FOUND")
        address_matches: bool | None = None
        region_complete = False
        if raw is not None:
            address_matches = normalize_address(row["address"]) == normalize_address(
                raw["도로명주소"]
            )
            if not address_matches:
                issues.append("SOURCE_ADDRESS_MISMATCH")
            region_complete = all(raw[field] for field in REGION_FIELDS)
        if not region_complete:
            issues.append("REGION_EVIDENCE_INCOMPLETE")
        result = {
            "storeId": row["storeId"],
            "candidateId": row["candidateId"],
            "name": row["name"],
            "approvedAddress": row["address"],
            "burgerStyle": row["burgerStyle"],
            "sourceAsOf": (row.get("sourceAsOf") or "").strip(),
            "sourceStoreId": source_id,
            "sourceStoreName": raw["상호명"] if raw else "",
            "sourceRoadAddress": raw["도로명주소"] if raw else "",
            "sourceLinked": str(raw is not None).lower(),
            "sourceAddressMatches": (
                "" if address_matches is None else str(address_matches).lower()
            ),
            "regionComplete": str(region_complete).lower(),
            "manualReviewRequired": "true",
            "issueCodes": "|".join(issues),
        }
        for source_field, output_field in region_output_fields.items():
            result[output_field] = raw[source_field] if raw else ""
        output.append({field: result[field] for field in AUDIT_HEADERS})
    return output, approved


def _read_dev_asset(path: Path) -> list[dict[str, object]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as error:
        raise RegionAuditError(f"개발 asset JSON을 읽을 수 없습니다: {path}") from error
    if not isinstance(data, list) or any(not isinstance(item, dict) for item in data):
        raise RegionAuditError(f"개발 asset JSON 형식이 잘못되었습니다: {path}")
    _require_unique(data, "id", "development asset")
    return data


def run_audit(
    publish_path: Path,
    staging_path: Path,
    raw_path: Path,
    local_snapshot_path: Path,
    dev_asset_path: Path,
    output_dir: Path,
) -> dict[str, object]:
    if output_dir.exists():
        raise RegionAuditError(f"출력 디렉터리가 이미 존재합니다: {output_dir}")
    _, publish_rows = _read_csv_rows_and_headers(publish_path, PUBLISH_FIELDS)
    _, staging_rows = _read_csv_rows_and_headers(staging_path, STAGING_FIELDS)
    local_headers, local_rows = _read_csv_rows_and_headers(
        local_snapshot_path, LOCAL_FIELDS
    )
    dev_items = _read_dev_asset(dev_asset_path)
    approved = select_approved_publish_rows(publish_rows)
    staging_by_candidate = _require_unique(staging_rows, "candidateId", "staging")
    referenced_ids = {
        (staging_by_candidate[row["candidateId"]].get("sourceStoreId") or "").strip()
        for row in approved
        if row["candidateId"] in staging_by_candidate
        and (
            staging_by_candidate[row["candidateId"]].get("sourceStoreId") or ""
        ).strip()
    }
    raw_by_id, raw_count = scan_raw_rows(raw_path, referenced_ids)
    audit_rows, approved = build_audit_rows(publish_rows, staging_rows, raw_by_id)
    approved_candidates = {row["candidateId"] for row in approved}
    asset_candidates = set(_require_unique(dev_items, "id", "development asset"))
    paths_and_counts = (
        ("publishReview", publish_path, len(publish_rows)),
        ("staging", staging_path, len(staging_rows)),
        ("rawCommercialStores", raw_path, raw_count),
        ("localSnapshot", local_snapshot_path, len(local_rows)),
        ("developmentAsset", dev_asset_path, len(dev_items)),
    )
    summary: dict[str, object] = {
        "auditBoundary": {
            "remoteChecked": False,
            "localSnapshotHasVerificationFields": LOCAL_VERIFICATION_FIELDS.issubset(
                local_headers
            ),
            "regionDataIsSourceEvidenceOnly": True,
            "everyRegionRequiresReview": True,
        },
        "inputs": {
            key: {
                "path": str(path.resolve()),
                "sha256": sha256_file(path),
                "rowCount": count,
            }
            for key, path, count in paths_and_counts
        },
        "counts": {
            "publishRows": len(publish_rows),
            "approvedTargetRows": len(approved),
            "excludedPublishRows": len(publish_rows) - len(approved),
            "sourceLinkedRows": sum(
                row["sourceLinked"] == "true" for row in audit_rows
            ),
            "sourceUnlinkedRows": sum(
                row["sourceLinked"] == "false" for row in audit_rows
            ),
            "regionCompleteRows": sum(
                row["regionComplete"] == "true" for row in audit_rows
            ),
            "regionIncompleteRows": sum(
                row["regionComplete"] == "false" for row in audit_rows
            ),
            "addressMismatchRows": sum(
                row["sourceAddressMatches"] == "false" for row in audit_rows
            ),
        },
        "localSnapshotComparison": _compare_local_snapshot(approved, local_rows),
        "developmentAssetCandidateComparison": {
            "candidateIdOnlyInApprovedTarget": sorted(
                approved_candidates - asset_candidates
            ),
            "candidateIdOnlyInDevelopmentAsset": sorted(
                asset_candidates - approved_candidates
            ),
        },
    }
    try:
        output_dir.mkdir(parents=True, exist_ok=False)
    except FileExistsError as error:
        raise RegionAuditError(f"출력 디렉터리가 이미 존재합니다: {output_dir}") from error
    except OSError as error:
        raise RegionAuditError(f"출력 디렉터리를 만들 수 없습니다: {output_dir}") from error
    audit_path = output_dir / "region_audit.csv"
    try:
        with audit_path.open("x", encoding="utf-8-sig", newline="") as destination:
            writer = csv.DictWriter(destination, fieldnames=AUDIT_HEADERS)
            writer.writeheader()
            writer.writerows(audit_rows)
        with (output_dir / "summary.json").open(
            "x", encoding="utf-8", newline=""
        ) as destination:
            destination.write(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    except OSError as error:
        raise RegionAuditError(f"감사 출력을 쓸 수 없습니다: {output_dir}") from error
    return summary


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", type=Path, default=DEFAULT_PUBLISH_PATH)
    parser.add_argument("--staging", type=Path, default=DEFAULT_STAGING_PATH)
    parser.add_argument("--raw", type=Path, default=DEFAULT_RAW_PATH)
    parser.add_argument(
        "--local-snapshot", type=Path, default=DEFAULT_LOCAL_SNAPSHOT_PATH
    )
    parser.add_argument("--dev-asset", type=Path, default=DEFAULT_DEV_ASSET_PATH)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        summary = run_audit(
            args.publish,
            args.staging,
            args.raw,
            args.local_snapshot,
            args.dev_asset,
            args.output_dir,
        )
    except RegionAuditError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2
    print(json.dumps(summary["counts"], ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
