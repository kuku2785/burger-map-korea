#!/usr/bin/env python3
"""Recheck Kakao place ids and addresses for two manual-review targets."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from discover_kakao_burger_candidates import (  # noqa: E402
    DEFAULT_ENV_PATH,
    KakaoKeywordClient,
    DiscoveryError,
    is_yongsan_address,
    names_equivalent,
    normalize_address_for_matching,
    normalize_name_for_matching,
    parse_coordinate,
    read_kakao_api_key,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_INPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_discovery_reviewed.csv"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_address_recheck.csv"
)
DEFAULT_TARGETS_PATH = (
    PROJECT_ROOT
    / "data"
    / "config"
    / "kakao_burger_address_recheck_targets.json"
)
MAX_API_CALLS = 6
PAGE_SIZE = 15
ALLOWED_DECISIONS = {
    "resolved_new_place",
    "resolved_existing_place",
    "conflicting_results",
    "no_result",
    "needs_manual_check",
}
OUTPUT_HEADERS = (
    "targetName",
    "previousSourcePlaceId",
    "previousAddress",
    "searchedQuery",
    "resultSourcePlaceId",
    "resultName",
    "resultRoadAddress",
    "resultLotAddress",
    "latitude",
    "longitude",
    "sourceCategory",
    "placeUrl",
    "addressMatch",
    "placeIdChanged",
    "recheckDecision",
    "recheckNote",
    "checkedAt",
)
REQUIRED_DOCUMENT_FIELDS = (
    "id",
    "place_name",
    "category_name",
    "address_name",
    "road_address_name",
    "x",
    "y",
    "place_url",
)


@dataclass(frozen=True)
class RecheckTarget:
    target_name: str
    previous_source_place_id: str
    previous_address: str
    expected_public_address: str
    queries: tuple[str, ...]


@dataclass(frozen=True)
class RecheckConfig:
    targets: tuple[RecheckTarget, ...]
    longitude: float
    latitude: float
    radius_meters: int

    @property
    def query_count(self) -> int:
        return sum(len(target.queries) for target in self.targets)


def load_recheck_config(path: Path) -> RecheckConfig:
    try:
        with path.open("r", encoding="utf-8-sig") as config_file:
            data = json.load(config_file)
    except OSError as error:
        raise DiscoveryError(f"주소 재검증 설정을 열 수 없습니다: {path}") from error
    except json.JSONDecodeError as error:
        raise DiscoveryError(f"주소 재검증 설정 JSON이 올바르지 않습니다: {path}") from error

    try:
        center = data["center"]
        longitude = float(center["longitude"])
        latitude = float(center["latitude"])
        radius_meters = int(center["radiusMeters"])
        raw_targets = data["targets"]
    except (KeyError, TypeError, ValueError):
        raise DiscoveryError("주소 재검증 설정 형식이 잘못됐습니다.") from None
    if not isinstance(raw_targets, list) or len(raw_targets) != 2:
        raise DiscoveryError("주소 재검증 대상은 정확히 2개여야 합니다.")

    targets: list[RecheckTarget] = []
    seen_place_ids: set[str] = set()
    for item in raw_targets:
        if not isinstance(item, dict):
            raise DiscoveryError("주소 재검증 대상 형식이 잘못됐습니다.")
        try:
            target_name = str(item["targetName"]).strip()
            previous_source_place_id = str(item["previousSourcePlaceId"]).strip()
            previous_address = str(item["previousAddress"]).strip()
            expected_public_address = str(item["expectedPublicAddress"]).strip()
            raw_queries = item["queries"]
        except KeyError:
            raise DiscoveryError("주소 재검증 대상 필드가 누락됐습니다.") from None
        if not isinstance(raw_queries, list):
            raise DiscoveryError("주소 재검증 queries는 목록이어야 합니다.")
        queries = tuple(
            query.strip()
            for query in raw_queries
            if isinstance(query, str) and query.strip()
        )
        if (
            not target_name
            or not previous_source_place_id
            or not previous_address
            or not expected_public_address
            or len(queries) != 3
            or len(set(queries)) != 3
            or previous_source_place_id in seen_place_ids
        ):
            raise DiscoveryError("주소 재검증 대상 값이 올바르지 않습니다.")
        seen_place_ids.add(previous_source_place_id)
        targets.append(
            RecheckTarget(
                target_name,
                previous_source_place_id,
                previous_address,
                expected_public_address,
                queries,
            )
        )

    config = RecheckConfig(tuple(targets), longitude, latitude, radius_meters)
    if config.query_count != MAX_API_CALLS:
        raise DiscoveryError("주소 재검증 검색어는 정확히 6개여야 합니다.")
    if not -180 <= longitude <= 180 or not -90 <= latitude <= 90:
        raise DiscoveryError("검색 중심 좌표가 유효하지 않습니다.")
    if not 0 <= radius_meters <= 20000:
        raise DiscoveryError("검색 반경은 0~20000m여야 합니다.")
    return config


def validate_reviewed_input(path: Path, config: RecheckConfig) -> None:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            rows = list(csv.DictReader(input_file))
    except OSError as error:
        raise DiscoveryError(f"reviewed CSV를 열 수 없습니다: {path}") from error
    targets_by_id = {
        target.previous_source_place_id: target for target in config.targets
    }
    found: dict[str, dict[str, str]] = {}
    for row in rows:
        source_place_id = (row.get("sourcePlaceId") or "").strip()
        if source_place_id in targets_by_id:
            if source_place_id in found:
                raise DiscoveryError("reviewed CSV에 대상 sourcePlaceId가 중복됐습니다.")
            found[source_place_id] = row
    if set(found) != set(targets_by_id):
        raise DiscoveryError("reviewed CSV의 주소 재검증 대상이 정확히 2개가 아닙니다.")
    for source_place_id, target in targets_by_id.items():
        row = found[source_place_id]
        if (
            row.get("name") != target.target_name
            or row.get("address") != target.previous_address
            or row.get("manualReviewAction") != "needs_address_check"
            or row.get("manualReviewStatus") != "needs_recheck"
        ):
            raise DiscoveryError(
                f"reviewed CSV의 대상 정보가 설정과 일치하지 않습니다: {source_place_id}"
            )


def classify_address(address: str, target: RecheckTarget) -> str:
    normalized = normalize_address_for_matching(address)
    expected = normalize_address_for_matching(target.expected_public_address)
    previous = normalize_address_for_matching(target.previous_address)
    if normalized and normalized == expected and normalized == previous:
        return "both"
    if normalized and normalized == expected:
        return "expected_public_address"
    if normalized and normalized == previous:
        return "previous_address"
    return "neither"


def target_name_matches(target_name: str, result_name: str) -> bool:
    if names_equivalent(target_name, result_name):
        return True
    normalized_target = normalize_name_for_matching(target_name)
    normalized_result = normalize_name_for_matching(result_name)
    return normalized_result == f"{normalized_target}점"


def document_to_result(
    target: RecheckTarget,
    query: str,
    document: Mapping[str, object],
) -> dict[str, str] | None:
    if not all(field in document for field in REQUIRED_DOCUMENT_FIELDS):
        return None
    result_name = str(document["place_name"]).strip()
    road_address = str(document["road_address_name"]).strip()
    lot_address = str(document["address_name"]).strip()
    latitude = parse_coordinate(str(document["y"]))
    longitude = parse_coordinate(str(document["x"]))
    result_source_place_id = str(document["id"]).strip()
    if (
        not result_source_place_id
        or not result_name
        or latitude is None
        or longitude is None
        or not target_name_matches(target.target_name, result_name)
        or not (is_yongsan_address(road_address) or is_yongsan_address(lot_address))
    ):
        return None
    comparison_address = road_address or lot_address
    return {
        "targetName": target.target_name,
        "previousSourcePlaceId": target.previous_source_place_id,
        "previousAddress": target.previous_address,
        "searchedQuery": query,
        "resultSourcePlaceId": result_source_place_id,
        "resultName": result_name,
        "resultRoadAddress": road_address,
        "resultLotAddress": lot_address,
        "latitude": str(document["y"]),
        "longitude": str(document["x"]),
        "sourceCategory": str(document["category_name"]).strip(),
        "placeUrl": str(document["place_url"]).strip(),
        "addressMatch": classify_address(comparison_address, target),
        "placeIdChanged": str(
            result_source_place_id != target.previous_source_place_id
        ).lower(),
        "recheckDecision": "",
        "recheckNote": "",
        "checkedAt": "",
    }


def determine_target_decision(
    target: RecheckTarget, rows: Sequence[Mapping[str, str]]
) -> tuple[str, str]:
    if not rows:
        return "no_result", "용산구 주소와 정규화 매장명이 일치하는 결과가 없음."
    observations = {
        (
            row["resultSourcePlaceId"],
            normalize_address_for_matching(
                row["resultRoadAddress"] or row["resultLotAddress"]
            ),
            row["latitude"],
            row["longitude"],
        )
        for row in rows
    }
    place_ids = {observation[0] for observation in observations}
    addresses = {observation[1] for observation in observations}
    coordinates = {(observation[2], observation[3]) for observation in observations}
    if len(place_ids) > 1 or len(addresses) > 1 or len(coordinates) > 1:
        return (
            "conflicting_results",
            "동일 대상에 서로 다른 place id, 주소 또는 좌표 결과가 있어 자동 확정하지 않음.",
        )

    only_row = rows[0]
    address_match = only_row["addressMatch"]
    place_id_changed = only_row["placeIdChanged"] == "true"
    if address_match in {"expected_public_address", "both"}:
        if place_id_changed:
            return (
                "resolved_new_place",
                "공개 확인 주소와 일치하는 새 place id가 단일 결과로 확인됨. verified 아님.",
            )
        return (
            "resolved_existing_place",
            "공개 확인 주소와 기존 place id가 단일 결과로 확인됨. verified 아님.",
        )
    if address_match == "previous_address" and not place_id_changed:
        return (
            "needs_manual_check",
            "기존 place id와 이전 주소만 확인되어 공개 확인 주소와의 차이를 수동 검토해야 함.",
        )
    return (
        "needs_manual_check",
        "단일 결과이나 예상 공개 주소 또는 기존 장소와 충분히 일치하지 않아 수동 검토가 필요함.",
    )


def recheck_addresses(
    *,
    client: KakaoKeywordClient,
    config: RecheckConfig,
    input_path: Path,
    output_path: Path,
    checked_at: str | None = None,
    overwrite: bool = False,
) -> tuple[list[dict[str, str]], int]:
    if output_path.exists() and not overwrite:
        raise DiscoveryError(
            f"출력 파일이 이미 존재합니다. 덮어쓰지 않았습니다: {output_path}"
        )
    validate_reviewed_input(input_path, config)
    timestamp = checked_at or datetime.now(timezone.utc).isoformat()
    all_rows: list[dict[str, str]] = []
    for target in config.targets:
        target_rows: list[dict[str, str]] = []
        for query in target.queries:
            documents, _ = client.search_page(
                query,
                longitude=config.longitude,
                latitude=config.latitude,
                radius_meters=config.radius_meters,
                page=1,
                size=PAGE_SIZE,
            )
            matching_rows = [
                row
                for document in documents
                if (row := document_to_result(target, query, document)) is not None
            ]
            if matching_rows:
                target_rows.extend(matching_rows)
            else:
                target_rows.append(
                    {
                        "targetName": target.target_name,
                        "previousSourcePlaceId": target.previous_source_place_id,
                        "previousAddress": target.previous_address,
                        "searchedQuery": query,
                        "resultSourcePlaceId": "",
                        "resultName": "",
                        "resultRoadAddress": "",
                        "resultLotAddress": "",
                        "latitude": "",
                        "longitude": "",
                        "sourceCategory": "",
                        "placeUrl": "",
                        "addressMatch": "none",
                        "placeIdChanged": "",
                        "recheckDecision": "",
                        "recheckNote": "",
                        "checkedAt": "",
                    }
                )
        result_rows = [row for row in target_rows if row["resultSourcePlaceId"]]
        decision, note = determine_target_decision(target, result_rows)
        if decision not in ALLOWED_DECISIONS:
            raise DiscoveryError("허용되지 않은 주소 재검증 판정이 생성됐습니다.")
        for row in target_rows:
            row["recheckDecision"] = decision
            row["recheckNote"] = note
            row["checkedAt"] = timestamp
        all_rows.extend(target_rows)

    if client.call_count != config.query_count or client.call_count > MAX_API_CALLS:
        raise DiscoveryError("실제 API 호출 수가 설정된 6회와 일치하지 않습니다.")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=OUTPUT_HEADERS)
        writer.writeheader()
        writer.writerows(all_rows)
    return all_rows, client.call_count


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="수동 검수 대상 2곳의 카카오 place id·주소·좌표를 재검증합니다."
    )
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--targets", type=Path, default=DEFAULT_TARGETS_PATH)
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV_PATH)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        config = load_recheck_config(args.targets)
        api_key = read_kakao_api_key(args.env_file)
        client = KakaoKeywordClient(api_key, max_api_calls=MAX_API_CALLS)
        rows, call_count = recheck_addresses(
            client=client,
            config=config,
            input_path=args.input,
            output_path=args.output,
            overwrite=args.overwrite,
        )
        decisions = {
            target.target_name: next(
                row["recheckDecision"]
                for row in rows
                if row["targetName"] == target.target_name
            )
            for target in config.targets
        }
        print(
            json.dumps(
                {
                    "대상 매장 수": len(config.targets),
                    "실제 API 호출 횟수": call_count,
                    "출력 행 수": len(rows),
                    "매장별 판정": decisions,
                    "출력 경로": str(args.output.resolve()),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except DiscoveryError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
