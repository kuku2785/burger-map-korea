#!/usr/bin/env python3
"""Build review-only Yongsan burger staging CSVs from approved pending links."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from discover_kakao_burger_candidates import (  # noqa: E402
    is_yongsan_address,
    normalize_address_for_matching,
    parse_coordinate,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_V2_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_candidates_v2.csv"
)
DEFAULT_REVIEWED_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_candidates_reviewed.csv"
)
DEFAULT_KAKAO_REVIEWED_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_discovery_reviewed.csv"
)
DEFAULT_ADDRESS_RECHECK_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_address_recheck.csv"
)
DEFAULT_HOLD_RULES_PATH = (
    PROJECT_ROOT / "data" / "config" / "yongsan_staging_hold_rules.json"
)
DEFAULT_ADDRESS_RESOLUTIONS_PATH = (
    PROJECT_ROOT / "data" / "config" / "manual_address_resolutions.json"
)
DEFAULT_STAGING_OUTPUT_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_stores_staging.csv"
)
DEFAULT_HOLD_OUTPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "staging"
    / "yongsan_burger_staging_hold_report.csv"
)

EXPECTED_LINK_COUNT = 14
EXPECTED_ADD_COUNT = 10
EXPECTED_STAGING_COUNT = 24
EXPECTED_HOLD_COUNT = 4
STAGING_HEADERS = (
    "candidateId",
    "displayName",
    "address",
    "latitude",
    "longitude",
    "stagingStatus",
    "sourceType",
    "sourceStoreId",
    "sourcePlaceId",
    "placeUrl",
    "matchedCandidateId",
    "sourceCategory",
    "verificationStatus",
    "addressConflict",
    "provenanceNote",
)
HOLD_HEADERS = (
    "candidateId",
    "sourcePlaceId",
    "name",
    "previousStatus",
    "stagingStatus",
    "holdReason",
    "recommendedAction",
)


class StagingError(ValueError):
    """Raised when staging inputs or output rows violate review safeguards."""


class AddressConflictError(StagingError):
    """Raised when a linked SEMAS and Kakao address cannot be selected safely."""

    def __init__(self, conflicts: Sequence[Mapping[str, str]]) -> None:
        self.conflicts = tuple(dict(conflict) for conflict in conflicts)
        descriptions = "; ".join(
            f"{item['candidateId']} ({item['displayName']}): "
            f"SEMAS={item['semasAddress']} / Kakao={item['kakaoAddress']}"
            for item in self.conflicts
        )
        super().__init__(f"주소 충돌로 staging 생성을 중단했습니다: {descriptions}")


@dataclass(frozen=True)
class InputData:
    v2_by_id: dict[str, dict[str, str]]
    reviewed_by_id: dict[str, dict[str, str]]
    kakao_rows: tuple[dict[str, str], ...]
    address_recheck_rows: tuple[dict[str, str], ...]


@dataclass(frozen=True)
class AddressResolution:
    candidate_id: str
    source_place_id: str
    source_address: str
    display_address: str
    lot_address: str
    building_name: str
    resolution_status: str
    resolution_note: str


def read_csv_rows(
    path: Path,
    required_headers: set[str],
) -> tuple[list[str], list[dict[str, str]]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            reader = csv.DictReader(input_file)
            headers = list(reader.fieldnames or [])
            rows = list(reader)
    except OSError as error:
        raise StagingError(f"입력 CSV를 열 수 없습니다: {path}") from error
    missing = sorted(required_headers - set(headers))
    if missing:
        raise StagingError(f"입력 CSV 필수 컬럼이 없습니다: {path}, {missing}")
    return headers, rows


def index_unique(
    rows: Sequence[dict[str, str]],
    field: str,
    path: Path,
) -> dict[str, dict[str, str]]:
    indexed: dict[str, dict[str, str]] = {}
    for row in rows:
        value = row.get(field, "").strip()
        if not value or value in indexed:
            raise StagingError(f"{field}가 비었거나 중복됐습니다: {path}, {value}")
        indexed[value] = row
    return indexed


def load_inputs(
    v2_path: Path,
    reviewed_path: Path,
    kakao_reviewed_path: Path,
    address_recheck_path: Path,
) -> InputData:
    _, v2_rows = read_csv_rows(
        v2_path,
        {"candidateId", "sourceStoreId", "name", "address", "verificationStatus"},
    )
    _, reviewed_rows = read_csv_rows(
        reviewed_path,
        {
            "candidateId",
            "sourceStoreId",
            "name",
            "address",
            "latitude",
            "longitude",
            "verificationStatus",
        },
    )
    _, kakao_rows = read_csv_rows(
        kakao_reviewed_path,
        {
            "sourcePlaceId",
            "name",
            "address",
            "latitude",
            "longitude",
            "sourceCategory",
            "placeUrl",
            "matchedCandidateId",
            "manualReviewStatus",
            "manualReviewAction",
        },
    )
    _, address_recheck_rows = read_csv_rows(
        address_recheck_path,
        {
            "targetName",
            "previousSourcePlaceId",
            "recheckDecision",
        },
    )
    v2_by_id = index_unique(v2_rows, "candidateId", v2_path)
    reviewed_by_id = index_unique(reviewed_rows, "candidateId", reviewed_path)
    if set(v2_by_id) != set(reviewed_by_id):
        raise StagingError("V2와 reviewed 상가 후보의 candidateId 집합이 다릅니다.")
    source_place_ids = [row["sourcePlaceId"].strip() for row in kakao_rows]
    if any(not value for value in source_place_ids) or len(source_place_ids) != len(
        set(source_place_ids)
    ):
        raise StagingError("Kakao reviewed sourcePlaceId가 비었거나 중복됐습니다.")
    return InputData(
        v2_by_id,
        reviewed_by_id,
        tuple(kakao_rows),
        tuple(address_recheck_rows),
    )


def load_hold_rules(path: Path) -> tuple[dict[str, str], ...]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except OSError as error:
        raise StagingError(f"보류 규칙을 열 수 없습니다: {path}") from error
    except json.JSONDecodeError as error:
        raise StagingError(f"보류 규칙 JSON이 올바르지 않습니다: {path}") from error
    entries = data.get("holds")
    if not isinstance(entries, list) or len(entries) != EXPECTED_HOLD_COUNT:
        raise StagingError("보류 규칙은 정확히 4개여야 합니다.")
    required = {
        "candidateId",
        "sourcePlaceId",
        "expectedName",
        "holdReason",
        "recommendedAction",
    }
    rules: list[dict[str, str]] = []
    for entry in entries:
        if not isinstance(entry, dict) or not required.issubset(entry):
            raise StagingError("보류 규칙 필드가 누락됐습니다.")
        rule = {key: str(entry[key]).strip() for key in required}
        if (
            not rule["candidateId"]
            or not rule["expectedName"]
            or not rule["holdReason"]
            or not rule["recommendedAction"]
        ):
            raise StagingError("보류 규칙 값이 비어 있습니다.")
        rules.append(rule)
    if len({rule["candidateId"] for rule in rules}) != EXPECTED_HOLD_COUNT:
        raise StagingError("보류 규칙 candidateId가 중복됐습니다.")
    return tuple(rules)


def load_address_resolutions(
    path: Path,
) -> dict[tuple[str, str], AddressResolution]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except OSError as error:
        raise StagingError(f"수동 주소 판정 설정을 열 수 없습니다: {path}") from error
    except json.JSONDecodeError as error:
        raise StagingError(f"수동 주소 판정 JSON이 올바르지 않습니다: {path}") from error
    entries = data.get("resolutions")
    if not isinstance(entries, list):
        raise StagingError("수동 주소 판정 resolutions는 목록이어야 합니다.")
    required = {
        "candidateId",
        "sourcePlaceId",
        "sourceAddress",
        "displayAddress",
        "lotAddress",
        "buildingName",
        "resolutionStatus",
        "resolutionNote",
    }
    resolutions: dict[tuple[str, str], AddressResolution] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not required.issubset(entry):
            raise StagingError("수동 주소 판정 필드가 누락됐습니다.")
        values = {field: str(entry[field]).strip() for field in required}
        if any(not value for value in values.values()):
            raise StagingError("수동 주소 판정 값이 비어 있습니다.")
        if values["resolutionStatus"] != "resolved_same_building_variant":
            raise StagingError("허용되지 않은 수동 주소 판정 상태입니다.")
        if not is_yongsan_address(values["displayAddress"]):
            raise StagingError("수동 주소 판정 표시 주소가 용산구가 아닙니다.")
        key = (values["candidateId"], values["sourcePlaceId"])
        if key in resolutions:
            raise StagingError("수동 주소 판정 candidateId/sourcePlaceId가 중복됐습니다.")
        resolutions[key] = AddressResolution(
            candidate_id=values["candidateId"],
            source_place_id=values["sourcePlaceId"],
            source_address=values["sourceAddress"],
            display_address=values["displayAddress"],
            lot_address=values["lotAddress"],
            building_name=values["buildingName"],
            resolution_status=values["resolutionStatus"],
            resolution_note=values["resolutionNote"],
        )
    return resolutions


def is_valid_coordinate(latitude_value: str, longitude_value: str) -> bool:
    latitude = parse_coordinate(latitude_value)
    longitude = parse_coordinate(longitude_value)
    return (
        latitude is not None
        and longitude is not None
        and -90 <= latitude <= 90
        and -180 <= longitude <= 180
        and latitude != 0
        and longitude != 0
    )


def included_kakao_rows(kakao_rows: Sequence[dict[str, str]]) -> list[dict[str, str]]:
    rows = [
        row
        for row in kakao_rows
        if row["manualReviewStatus"] == "pending"
        and row["manualReviewAction"] in {"link_existing", "add_pending"}
    ]
    counts = Counter(row["manualReviewAction"] for row in rows)
    if counts != Counter(
        {"link_existing": EXPECTED_LINK_COUNT, "add_pending": EXPECTED_ADD_COUNT}
    ):
        raise StagingError(f"Kakao 포함 대상 집계가 예상과 다릅니다: {dict(counts)}")
    return rows


def build_staging_rows(
    inputs: InputData,
    address_resolutions: Mapping[tuple[str, str], AddressResolution],
    forbidden_candidate_ids: set[str] | frozenset[str] = frozenset(),
) -> list[dict[str, str]]:
    output_rows: list[dict[str, str]] = []
    conflicts: list[dict[str, str]] = []
    for kakao in included_kakao_rows(inputs.kakao_rows):
        action = kakao["manualReviewAction"]
        place_id = kakao["sourcePlaceId"].strip()
        name = kakao["name"].strip()
        address = kakao["address"].strip()
        latitude = kakao["latitude"].strip()
        longitude = kakao["longitude"].strip()
        if (
            not name
            or not address
            or not is_yongsan_address(address)
            or not is_valid_coordinate(latitude, longitude)
        ):
            raise StagingError(f"Kakao 후보 필수 값이 유효하지 않습니다: {place_id}")

        if action == "link_existing":
            candidate_id = kakao["matchedCandidateId"].strip()
            existing = inputs.reviewed_by_id.get(candidate_id)
            if not candidate_id or existing is None:
                raise StagingError(f"연결할 상가 candidateId가 없습니다: {place_id}")
            if existing["verificationStatus"] != "pending":
                raise StagingError(f"연결 상가 후보가 pending이 아닙니다: {candidate_id}")
            if inputs.v2_by_id[candidate_id]["sourceStoreId"] != existing["sourceStoreId"]:
                raise StagingError(f"sourceStoreId가 V2와 reviewed에서 다릅니다: {candidate_id}")
            if normalize_address_for_matching(existing["address"]) != (
                normalize_address_for_matching(address)
            ):
                resolution = address_resolutions.get((candidate_id, place_id))
                if resolution is None:
                    conflicts.append(
                        {
                            "candidateId": candidate_id,
                            "displayName": name,
                            "semasAddress": existing["address"],
                            "kakaoAddress": address,
                        }
                    )
                    address_conflict = ""
                    provenance_note = ""
                elif (
                    resolution.source_address != existing["address"]
                    or resolution.display_address != address
                ):
                    raise StagingError(
                        "수동 주소 판정의 원본 또는 표시 주소가 입력 CSV와 다릅니다: "
                        f"{candidate_id}, {place_id}"
                    )
                else:
                    address = resolution.display_address
                    address_conflict = resolution.resolution_status
                    provenance_note = resolution.resolution_note
            else:
                address_conflict = ""
                provenance_note = (
                    "상가정보 pending 후보와 수동 동일 매장 판정된 Kakao 장소를 연결함. "
                    "아직 verified 아님."
                )
            row = {
                "candidateId": candidate_id,
                "displayName": name,
                "address": address,
                "latitude": latitude,
                "longitude": longitude,
                "stagingStatus": "candidate_pending",
                "sourceType": "semas_kakao",
                "sourceStoreId": existing["sourceStoreId"],
                "sourcePlaceId": place_id,
                "placeUrl": kakao["placeUrl"].strip(),
                "matchedCandidateId": candidate_id,
                "sourceCategory": kakao["sourceCategory"].strip(),
                "verificationStatus": "pending",
                "addressConflict": address_conflict,
                "provenanceNote": provenance_note,
            }
        else:
            candidate_id = f"kakao_{place_id}"
            row = {
                "candidateId": candidate_id,
                "displayName": name,
                "address": address,
                "latitude": latitude,
                "longitude": longitude,
                "stagingStatus": "candidate_pending",
                "sourceType": "kakao",
                "sourceStoreId": "",
                "sourcePlaceId": place_id,
                "placeUrl": kakao["placeUrl"].strip(),
                "matchedCandidateId": "",
                "sourceCategory": kakao["sourceCategory"].strip(),
                "verificationStatus": "pending",
                "addressConflict": "",
                "provenanceNote": (
                    "Kakao 수동검수 add_pending 후보. 검수용 staging이며 아직 verified 아님."
                ),
            }
        output_rows.append(row)

    if conflicts:
        raise AddressConflictError(conflicts)
    validate_staging_rows(output_rows, forbidden_candidate_ids)
    return output_rows


def validate_staging_rows(
    rows: Sequence[Mapping[str, str]],
    forbidden_candidate_ids: set[str] | frozenset[str] = frozenset(),
) -> None:
    if len(rows) != EXPECTED_STAGING_COUNT:
        raise StagingError(f"staging 행 수가 24가 아닙니다: {len(rows)}")
    source_counts = Counter(row["sourceType"] for row in rows)
    if source_counts != Counter(
        {"semas_kakao": EXPECTED_LINK_COUNT, "kakao": EXPECTED_ADD_COUNT}
    ):
        raise StagingError(f"sourceType 집계가 예상과 다릅니다: {dict(source_counts)}")
    candidate_ids = [row["candidateId"] for row in rows]
    place_ids = [row["sourcePlaceId"] for row in rows]
    if len(candidate_ids) != len(set(candidate_ids)):
        raise StagingError("staging candidateId가 중복됐습니다.")
    if len(place_ids) != len(set(place_ids)) or any(not value for value in place_ids):
        raise StagingError("staging sourcePlaceId가 비었거나 중복됐습니다.")
    for row in rows:
        if (
            not row["displayName"]
            or not row["address"]
            or not is_valid_coordinate(row["latitude"], row["longitude"])
        ):
            raise StagingError(f"staging 필수 값이 누락됐습니다: {row['candidateId']}")
        if row["stagingStatus"] != "candidate_pending":
            raise StagingError("stagingStatus에 금지 상태가 포함됐습니다.")
        if row["verificationStatus"] != "pending":
            raise StagingError("verificationStatus에 pending 외 상태가 포함됐습니다.")
        if row["sourceType"] not in {"semas_kakao", "kakao"}:
            raise StagingError("허용되지 않은 sourceType이 포함됐습니다.")
        if row["addressConflict"] not in {"", "resolved_same_building_variant"}:
            raise StagingError("해소되지 않은 addressConflict가 staging에 포함됐습니다.")
    if forbidden_candidate_ids & set(candidate_ids):
        raise StagingError("보류 대상이 staging에 포함됐습니다.")


def build_hold_rows(
    inputs: InputData,
    rules: Sequence[Mapping[str, str]],
) -> list[dict[str, str]]:
    kakao_by_place_id = {
        row["sourcePlaceId"]: row for row in inputs.kakao_rows
    }
    recheck_by_place_id: dict[str, set[str]] = {}
    for row in inputs.address_recheck_rows:
        recheck_by_place_id.setdefault(
            row["previousSourcePlaceId"], set()
        ).add(row["recheckDecision"])
    output_rows: list[dict[str, str]] = []
    for rule in rules:
        candidate_id = rule["candidateId"]
        place_id = rule["sourcePlaceId"]
        if place_id:
            source = kakao_by_place_id.get(place_id)
            if source is None or source["name"] != rule["expectedName"]:
                raise StagingError(f"Kakao 보류 대상이 없거나 이름이 다릅니다: {place_id}")
            if (
                source["manualReviewStatus"] != "needs_recheck"
                or source["manualReviewAction"] != "needs_address_check"
                or recheck_by_place_id.get(place_id) != {"needs_manual_check"}
            ):
                raise StagingError(f"Kakao 주소 보류 상태가 예상과 다릅니다: {place_id}")
            previous_status = source["manualReviewStatus"]
            name = source["name"]
        else:
            source = inputs.reviewed_by_id.get(candidate_id)
            if source is None or source["name"] != rule["expectedName"]:
                raise StagingError(f"상가 보류 대상이 없거나 이름이 다릅니다: {candidate_id}")
            if source["verificationStatus"] != "pending":
                raise StagingError(f"상가 보류 대상이 pending이 아닙니다: {candidate_id}")
            previous_status = source["verificationStatus"]
            name = source["name"]
        output_rows.append(
            {
                "candidateId": candidate_id,
                "sourcePlaceId": place_id,
                "name": name,
                "previousStatus": previous_status,
                "stagingStatus": "hold_needs_recheck",
                "holdReason": rule["holdReason"],
                "recommendedAction": rule["recommendedAction"],
            }
        )
    validate_hold_rows(output_rows)
    return output_rows


def validate_hold_rows(rows: Sequence[Mapping[str, str]]) -> None:
    if len(rows) != EXPECTED_HOLD_COUNT:
        raise StagingError(f"보류 보고서 행 수가 4가 아닙니다: {len(rows)}")
    if len({row["candidateId"] for row in rows}) != EXPECTED_HOLD_COUNT:
        raise StagingError("보류 보고서 candidateId가 중복됐습니다.")
    if any(row["stagingStatus"] != "hold_needs_recheck" for row in rows):
        raise StagingError("보류 보고서 stagingStatus가 올바르지 않습니다.")
    if any(row["previousStatus"] in {"verified", "rejected"} for row in rows):
        raise StagingError("보류 대상을 verified 또는 rejected로 변경할 수 없습니다.")


def write_csv(
    path: Path,
    headers: Sequence[str],
    rows: Sequence[Mapping[str, str]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def generate_staging(
    *,
    v2_path: Path,
    reviewed_path: Path,
    kakao_reviewed_path: Path,
    address_recheck_path: Path,
    hold_rules_path: Path,
    address_resolutions_path: Path,
    staging_output_path: Path,
    hold_output_path: Path,
    overwrite: bool = False,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    existing_outputs = [
        path
        for path in (staging_output_path, hold_output_path)
        if path.exists()
    ]
    if existing_outputs and not overwrite:
        raise StagingError(f"출력 파일이 이미 존재합니다: {existing_outputs}")
    inputs = load_inputs(
        v2_path,
        reviewed_path,
        kakao_reviewed_path,
        address_recheck_path,
    )
    hold_rows = build_hold_rows(inputs, load_hold_rules(hold_rules_path))
    forbidden_candidate_ids = {row["candidateId"] for row in hold_rows}
    address_resolutions = load_address_resolutions(address_resolutions_path)
    try:
        staging_rows = build_staging_rows(
            inputs,
            address_resolutions,
            forbidden_candidate_ids,
        )
    except AddressConflictError:
        write_csv(hold_output_path, HOLD_HEADERS, hold_rows)
        raise
    write_csv(staging_output_path, STAGING_HEADERS, staging_rows)
    write_csv(hold_output_path, HOLD_HEADERS, hold_rows)
    return staging_rows, hold_rows


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="상가정보와 Kakao 수동검수 결과를 Flutter 반영 전 staging CSV로 통합합니다."
    )
    parser.add_argument("--v2", type=Path, default=DEFAULT_V2_PATH)
    parser.add_argument("--reviewed", type=Path, default=DEFAULT_REVIEWED_PATH)
    parser.add_argument("--kakao-reviewed", type=Path, default=DEFAULT_KAKAO_REVIEWED_PATH)
    parser.add_argument("--address-recheck", type=Path, default=DEFAULT_ADDRESS_RECHECK_PATH)
    parser.add_argument("--hold-rules", type=Path, default=DEFAULT_HOLD_RULES_PATH)
    parser.add_argument(
        "--address-resolutions",
        type=Path,
        default=DEFAULT_ADDRESS_RESOLUTIONS_PATH,
    )
    parser.add_argument("--staging-output", type=Path, default=DEFAULT_STAGING_OUTPUT_PATH)
    parser.add_argument("--hold-output", type=Path, default=DEFAULT_HOLD_OUTPUT_PATH)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        staging_rows, hold_rows = generate_staging(
            v2_path=args.v2,
            reviewed_path=args.reviewed,
            kakao_reviewed_path=args.kakao_reviewed,
            address_recheck_path=args.address_recheck,
            hold_rules_path=args.hold_rules,
            address_resolutions_path=args.address_resolutions,
            staging_output_path=args.staging_output,
            hold_output_path=args.hold_output,
            overwrite=args.overwrite,
        )
        print(
            json.dumps(
                {
                    "stagingRows": len(staging_rows),
                    "sourceType": dict(Counter(row["sourceType"] for row in staging_rows)),
                    "holdRows": len(hold_rows),
                    "stagingOutput": str(args.staging_output.resolve()),
                    "holdOutput": str(args.hold_output.resolve()),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except StagingError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
