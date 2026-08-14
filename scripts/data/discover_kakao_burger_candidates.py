#!/usr/bin/env python3
"""Discover Yongsan burger candidates with Kakao keyword place search."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from extract_burger_candidates import (  # noqa: E402
    DEFAULT_EXCLUSION_RULES_PATH,
    contains_keyword,
    load_exclusion_rules,
    match_exclusion_rules,
    normalize_for_comparison,
    normalize_name_for_matching,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
API_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"
DEFAULT_QUERY_CONFIG_PATH = (
    PROJECT_ROOT / "data" / "config" / "kakao_burger_search_queries.json"
)
DEFAULT_V2_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_candidates_v2.csv"
)
DEFAULT_REVIEWED_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_burger_candidates_reviewed.csv"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT
    / "data"
    / "review"
    / "yongsan_kakao_burger_discovery.csv"
)
DEFAULT_ENV_PATH = PROJECT_ROOT / ".env"
PAGE_SIZE = 15
MAX_PAGE = 45
DEFAULT_TIMEOUT_SECONDS = 15.0
EXISTING_DISTANCE_METERS = 100.0
POSSIBLE_DUPLICATE_DISTANCE_METERS = 50.0
BURGER_TERMS = ("버거", "햄버거", "수제버거", "burger", "hamburger")
CLEAR_CATEGORY_TERMS = ("버거", "햄버거", "수제버거", "패스트푸드")
OUTPUT_HEADERS = (
    "discoveryId",
    "source",
    "sourcePlaceId",
    "name",
    "address",
    "latitude",
    "longitude",
    "sourceCategory",
    "matchedQueries",
    "placeUrl",
    "matchStatus",
    "matchedCandidateId",
    "screeningStatus",
    "screeningFlags",
    "conflictWithReviewed",
    "discoveredAt",
)
REQUIRED_KAKAO_FIELDS = (
    "id",
    "place_name",
    "category_name",
    "address_name",
    "road_address_name",
    "x",
    "y",
    "place_url",
)


class DiscoveryError(RuntimeError):
    """Base error for safe, user-facing discovery failures."""


class MissingApiKeyError(DiscoveryError):
    """Raised when no Kakao REST API key is configured."""


class KakaoApiError(DiscoveryError):
    """Raised for Kakao HTTP, quota, authentication, or network failures."""


@dataclass(frozen=True)
class SearchConfig:
    queries: tuple[str, ...]
    longitude: float
    latitude: float
    radius_meters: int

    @property
    def maximum_calls(self) -> int:
        return len(self.queries) * MAX_PAGE

    @property
    def minimum_calls(self) -> int:
        return len(self.queries)


@dataclass
class DiscoveryStats:
    api_calls: int = 0
    raw_results_by_query: Counter[str] = field(default_factory=Counter)
    yongsan_results_by_query: Counter[str] = field(default_factory=Counter)
    excluded_by_rule: Counter[str] = field(default_factory=Counter)
    invalid_documents: int = 0
    deduplicated_places: int = 0
    match_status_counts: Counter[str] = field(default_factory=Counter)
    screening_status_counts: Counter[str] = field(default_factory=Counter)
    conflict_with_reviewed: int = 0

    def as_dict(self, output_path: Path) -> dict[str, object]:
        return {
            "실제 API 호출 횟수": self.api_calls,
            "검색어별 원시 결과 개수": dict(self.raw_results_by_query),
            "검색어별 용산구 필터 통과 개수": dict(
                self.yongsan_results_by_query
            ),
            "제외 규칙별 개수": dict(sorted(self.excluded_by_rule.items())),
            "필수 필드 또는 좌표 오류 수": self.invalid_documents,
            "중복 제거 후 장소 수": self.deduplicated_places,
            "matchStatus별 개수": dict(sorted(self.match_status_counts.items())),
            "screeningStatus별 개수": dict(
                sorted(self.screening_status_counts.items())
            ),
            "reviewed 충돌 수": self.conflict_with_reviewed,
            "출력 CSV 행 수": self.deduplicated_places,
            "출력 경로": str(output_path.resolve()),
        }


Transport = Callable[[str, Mapping[str, str], float], Mapping[str, object]]


class KakaoKeywordClient:
    def __init__(
        self,
        api_key: str,
        *,
        transport: Transport | None = None,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        max_api_calls: int = MAX_PAGE * 100,
    ) -> None:
        if not api_key.strip():
            raise MissingApiKeyError(
                "KAKAO_REST_API_KEY가 설정되지 않았습니다."
            )
        self._api_key = api_key
        self._transport = transport or request_json
        self._timeout_seconds = timeout_seconds
        self._max_api_calls = max_api_calls
        self.call_count = 0

    def search_page(
        self,
        query: str,
        *,
        longitude: float,
        latitude: float,
        radius_meters: int,
        page: int = 1,
        size: int = PAGE_SIZE,
    ) -> tuple[list[dict[str, object]], bool]:
        if not 1 <= page <= MAX_PAGE:
            raise DiscoveryError("카카오 검색 page는 1~45여야 합니다.")
        if not 1 <= size <= PAGE_SIZE:
            raise DiscoveryError("카카오 검색 size는 1~15여야 합니다.")
        if self.call_count >= self._max_api_calls:
            raise DiscoveryError(
                "안전 호출 한도를 초과할 수 있어 실행을 중단했습니다."
            )
        parameters = {
            "query": query,
            "x": str(longitude),
            "y": str(latitude),
            "radius": str(radius_meters),
            "page": str(page),
            "size": str(size),
            "sort": "accuracy",
        }
        url = API_URL + "?" + urllib.parse.urlencode(parameters)
        headers = {"Authorization": f"KakaoAK {self._api_key}"}
        self.call_count += 1
        response = self._transport(url, headers, self._timeout_seconds)
        return parse_search_page(response)

    def search_all(
        self,
        query: str,
        *,
        longitude: float,
        latitude: float,
        radius_meters: int,
    ) -> list[dict[str, object]]:
        documents: list[dict[str, object]] = []
        for page in range(1, MAX_PAGE + 1):
            page_documents, is_end = self.search_page(
                query,
                longitude=longitude,
                latitude=latitude,
                radius_meters=radius_meters,
                page=page,
            )
            documents.extend(page_documents)
            if is_end:
                break
        return documents


def request_json(
    url: str, headers: Mapping[str, str], timeout_seconds: float
) -> Mapping[str, object]:
    request = urllib.request.Request(url, headers=dict(headers), method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        if error.code == 401:
            raise KakaoApiError(
                "카카오 API 인증에 실패했습니다(HTTP 401). REST API 키를 확인하세요."
            ) from None
        if error.code == 403:
            raise KakaoApiError(
                "카카오 API 사용 권한이 없습니다(HTTP 403). 카카오맵 사용 설정을 확인하세요."
            ) from None
        if error.code == 429:
            raise KakaoApiError(
                "카카오 API 쿼터 또는 요청 한도에 도달했습니다(HTTP 429). 재시도하지 않았습니다."
            ) from None
        raise KakaoApiError(
            f"카카오 API 요청이 실패했습니다(HTTP {error.code})."
        ) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise KakaoApiError(
            "카카오 API 네트워크 요청에 실패했습니다. 자동 재시도하지 않았습니다."
        ) from None

    try:
        decoded = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise KakaoApiError("카카오 API 응답 JSON을 해석할 수 없습니다.") from None
    if not isinstance(decoded, dict):
        raise KakaoApiError("카카오 API 응답 형식이 올바르지 않습니다.")
    return decoded


def parse_search_page(
    response: Mapping[str, object]
) -> tuple[list[dict[str, object]], bool]:
    documents = response.get("documents")
    meta = response.get("meta")
    if not isinstance(documents, list) or not isinstance(meta, dict):
        raise KakaoApiError("카카오 API 응답에 documents 또는 meta가 없습니다.")
    if not isinstance(meta.get("is_end"), bool):
        raise KakaoApiError("카카오 API 응답에 유효한 is_end가 없습니다.")
    return [item for item in documents if isinstance(item, dict)], meta["is_end"]


def load_search_config(path: Path) -> SearchConfig:
    try:
        with path.open("r", encoding="utf-8-sig") as config_file:
            data = json.load(config_file)
    except OSError as error:
        raise DiscoveryError(f"검색어 설정 파일을 열 수 없습니다: {path}") from error
    except json.JSONDecodeError as error:
        raise DiscoveryError(f"검색어 설정 JSON이 올바르지 않습니다: {path}") from error

    try:
        queries = tuple(
            dict.fromkeys(
                query.strip()
                for query in data["queries"]
                if isinstance(query, str) and query.strip()
            )
        )
        center = data["center"]
        longitude = float(center["longitude"])
        latitude = float(center["latitude"])
        radius_meters = int(center["radiusMeters"])
    except (KeyError, TypeError, ValueError):
        raise DiscoveryError("검색어 설정의 queries 또는 center 형식이 잘못됐습니다.") from None

    if not queries:
        raise DiscoveryError("검색어 설정에 검색어가 없습니다.")
    if not -180 <= longitude <= 180 or not -90 <= latitude <= 90:
        raise DiscoveryError("검색 중심 좌표가 유효하지 않습니다.")
    if not 0 <= radius_meters <= 20000:
        raise DiscoveryError("검색 반경은 카카오 공식 제한인 0~20000m여야 합니다.")
    return SearchConfig(queries, longitude, latitude, radius_meters)


def read_kakao_api_key(env_path: Path, environ: Mapping[str, str] | None = None) -> str:
    environment = environ if environ is not None else os.environ
    environment_value = environment.get("KAKAO_REST_API_KEY", "").strip()
    if environment_value:
        return environment_value

    try:
        lines = env_path.read_text(encoding="utf-8-sig").splitlines()
    except OSError:
        lines = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        if key.strip() != "KAKAO_REST_API_KEY":
            continue
        parsed = value.strip()
        if len(parsed) >= 2 and parsed[0] == parsed[-1] and parsed[0] in {'"', "'"}:
            parsed = parsed[1:-1]
        if parsed:
            return parsed
    raise MissingApiKeyError(
        "KAKAO_REST_API_KEY가 설정되지 않았습니다. .env 또는 환경변수를 확인하세요."
    )


def is_yongsan_address(address: str) -> bool:
    normalized = normalize_for_comparison(address).replace("특별시", "")
    return normalized.startswith("서울 용산구 ") or normalized == "서울 용산구"


def is_burger_related(category: str, queries: Sequence[str]) -> bool:
    return contains_keyword(category, BURGER_TERMS) or any(
        contains_keyword(query, BURGER_TERMS) for query in queries
    )


def has_clear_burger_category(category: str) -> bool:
    return contains_keyword(category, CLEAR_CATEGORY_TERMS)


def normalize_address_for_matching(value: str) -> str:
    normalized = normalize_for_comparison(value).replace("특별시", "")
    return "".join(character for character in normalized if character.isalnum())


def name_variants(value: str) -> frozenset[str]:
    normalized = normalize_name_for_matching(value)
    variants = {normalized} if normalized else set()
    spaced = normalize_for_comparison(value)
    tokens = spaced.split()
    if len(tokens) > 1 and tokens[-1].endswith("점"):
        variants.add(normalize_name_for_matching(" ".join(tokens[:-1])))
    for suffix in (
        "이태원점",
        "한남점",
        "한남동점",
        "용산점",
        "신용산점",
        "숙대점",
        "숙명여대점",
        "후암점",
        "후암동점",
        "이촌점",
        "이촌동점",
        "삼각지역점",
    ):
        normalized_suffix = normalize_name_for_matching(suffix)
        if normalized.endswith(normalized_suffix) and len(normalized) > len(normalized_suffix):
            variants.add(normalized[: -len(normalized_suffix)])
    return frozenset(variant for variant in variants if variant)


def names_equivalent(left: str, right: str) -> bool:
    left_variants = name_variants(left)
    right_variants = name_variants(right)
    return bool(left_variants & right_variants)


def coordinate_distance_meters(
    latitude_a: float,
    longitude_a: float,
    latitude_b: float,
    longitude_b: float,
) -> float:
    earth_radius = 6371000.0
    lat_a = math.radians(latitude_a)
    lat_b = math.radians(latitude_b)
    delta_lat = math.radians(latitude_b - latitude_a)
    delta_lng = math.radians(longitude_b - longitude_a)
    value = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat_a) * math.cos(lat_b) * math.sin(delta_lng / 2) ** 2
    )
    return 2 * earth_radius * math.asin(math.sqrt(value))


def parse_coordinate(value: str | None) -> float | None:
    try:
        parsed = float(value or "")
    except ValueError:
        return None
    return parsed if math.isfinite(parsed) else None


def load_csv_by_candidate_id(path: Path) -> dict[str, dict[str, str]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            rows = list(csv.DictReader(input_file))
    except OSError as error:
        raise DiscoveryError(f"기존 후보 CSV를 열 수 없습니다: {path}") from error
    result: dict[str, dict[str, str]] = {}
    for row in rows:
        candidate_id = (row.get("candidateId") or "").strip()
        if not candidate_id:
            raise DiscoveryError(f"candidateId가 비어 있는 행이 있습니다: {path}")
        if candidate_id in result:
            raise DiscoveryError(f"candidateId가 중복됐습니다: {path}")
        result[candidate_id] = row
    return result


def build_existing_records(
    v2_path: Path, reviewed_path: Path
) -> tuple[list[dict[str, str]], dict[str, str]]:
    v2 = load_csv_by_candidate_id(v2_path)
    reviewed = load_csv_by_candidate_id(reviewed_path)
    reviewed_status = {
        candidate_id: row.get("verificationStatus", "")
        for candidate_id, row in reviewed.items()
    }
    records = list(v2.values())
    for candidate_id, row in reviewed.items():
        if candidate_id not in v2:
            records.append(row)
    return records, reviewed_status


def match_existing_candidate(
    place: Mapping[str, object], existing_records: Sequence[Mapping[str, str]]
) -> tuple[str, str]:
    place_name = str(place["place_name"])
    place_address = str(place["address"])
    place_latitude = parse_coordinate(str(place["y"]))
    place_longitude = parse_coordinate(str(place["x"]))
    best_existing: tuple[float, str] | None = None
    best_possible: tuple[float, str] | None = None

    for candidate in existing_records:
        candidate_id = candidate.get("candidateId", "")
        if not candidate_id:
            continue
        same_name = names_equivalent(place_name, candidate.get("name", ""))
        same_address = (
            normalize_address_for_matching(place_address)
            == normalize_address_for_matching(candidate.get("address", ""))
        )
        candidate_latitude = parse_coordinate(candidate.get("latitude"))
        candidate_longitude = parse_coordinate(candidate.get("longitude"))
        distance = math.inf
        if (
            place_latitude is not None
            and place_longitude is not None
            and candidate_latitude is not None
            and candidate_longitude is not None
        ):
            distance = coordinate_distance_meters(
                place_latitude,
                place_longitude,
                candidate_latitude,
                candidate_longitude,
            )

        if same_name and (same_address or distance <= EXISTING_DISTANCE_METERS):
            score = 0.0 if same_address else distance
            if best_existing is None or (score, candidate_id) < best_existing:
                best_existing = (score, candidate_id)
        elif same_address or distance <= POSSIBLE_DUPLICATE_DISTANCE_METERS:
            score = 0.0 if same_address else distance
            if best_possible is None or (score, candidate_id) < best_possible:
                best_possible = (score, candidate_id)

    if best_existing is not None:
        return "existing_match", best_existing[1]
    if best_possible is not None:
        return "possible_duplicate", best_possible[1]
    return "new_candidate", ""


def collect_places(
    client: KakaoKeywordClient,
    config: SearchConfig,
    exclusion_rules: Sequence[dict[str, object]],
    stats: DiscoveryStats,
) -> dict[str, dict[str, object]]:
    places: dict[str, dict[str, object]] = {}
    excluded_place_ids_by_rule: defaultdict[str, set[str]] = defaultdict(set)
    for query in config.queries:
        documents = client.search_all(
            query,
            longitude=config.longitude,
            latitude=config.latitude,
            radius_meters=config.radius_meters,
        )
        stats.raw_results_by_query[query] += len(documents)
        for document in documents:
            if not all(field in document for field in REQUIRED_KAKAO_FIELDS):
                stats.invalid_documents += 1
                continue
            place_id = str(document["id"]).strip()
            name = str(document["place_name"]).strip()
            category = str(document["category_name"]).strip()
            road_address = str(document["road_address_name"]).strip()
            parcel_address = str(document["address_name"]).strip()
            address = road_address or parcel_address
            latitude = parse_coordinate(str(document["y"]))
            longitude = parse_coordinate(str(document["x"]))
            if not place_id or not name or not address or latitude is None or longitude is None:
                stats.invalid_documents += 1
                continue
            if not is_yongsan_address(address) and not is_yongsan_address(parcel_address):
                continue
            stats.yongsan_results_by_query[query] += 1
            if not is_burger_related(category, (query,)):
                continue

            exclusion_reasons = match_exclusion_rules(
                {"상호명": name, "sourceCategory": category},
                exclusion_rules,
            )
            if exclusion_reasons:
                for exclusion_reason in exclusion_reasons:
                    excluded_place_ids_by_rule[exclusion_reason].add(place_id)
                continue

            if place_id not in places:
                places[place_id] = {
                    "id": place_id,
                    "place_name": name,
                    "category_name": category,
                    "address": address,
                    "address_name": parcel_address,
                    "road_address_name": road_address,
                    "x": str(document["x"]),
                    "y": str(document["y"]),
                    "place_url": str(document["place_url"]).strip(),
                    "matched_queries": set(),
                }
            matched_queries = places[place_id]["matched_queries"]
            if isinstance(matched_queries, set):
                matched_queries.add(query)
    stats.api_calls = client.call_count
    stats.excluded_by_rule.update(
        {
            reason: len(place_ids)
            for reason, place_ids in excluded_place_ids_by_rule.items()
        }
    )
    stats.deduplicated_places = len(places)
    return places


def build_output_rows(
    places: Mapping[str, Mapping[str, object]],
    existing_records: Sequence[Mapping[str, str]],
    reviewed_status: Mapping[str, str],
    discovered_at: str,
    stats: DiscoveryStats,
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for place_id in sorted(places):
        place = places[place_id]
        match_status, matched_candidate_id = match_existing_candidate(
            place, existing_records
        )
        flags: list[str] = []
        if not has_clear_burger_category(str(place["category_name"])):
            flags.append("ambiguous_category")
        if match_status == "possible_duplicate":
            flags.append("possible_duplicate")

        conflict = bool(
            match_status == "existing_match"
            and
            matched_candidate_id
            and reviewed_status.get(matched_candidate_id) == "rejected"
        )
        if conflict:
            flags.append("conflict_with_reviewed")
            stats.conflict_with_reviewed += 1

        screening_status = "needs_recheck" if flags else "pending"
        matched_queries = place.get("matched_queries", set())
        query_list = sorted(matched_queries) if isinstance(matched_queries, set) else []
        row = {
            "discoveryId": f"kakao_{place_id}",
            "source": "kakao_local",
            "sourcePlaceId": place_id,
            "name": str(place["place_name"]),
            "address": str(place["address"]),
            "latitude": str(place["y"]),
            "longitude": str(place["x"]),
            "sourceCategory": str(place["category_name"]),
            "matchedQueries": json.dumps(query_list, ensure_ascii=False),
            "placeUrl": str(place["place_url"]),
            "matchStatus": match_status,
            "matchedCandidateId": matched_candidate_id,
            "screeningStatus": screening_status,
            "screeningFlags": ";".join(flags),
            "conflictWithReviewed": str(conflict).lower(),
            "discoveredAt": discovered_at,
        }
        if screening_status == "verified":
            raise DiscoveryError("자동 verified 상태 생성이 감지됐습니다.")
        rows.append(row)
        stats.match_status_counts[match_status] += 1
        stats.screening_status_counts[screening_status] += 1
    return rows


def write_output(path: Path, rows: Sequence[Mapping[str, str]], *, overwrite: bool) -> None:
    if path.exists() and not overwrite:
        raise DiscoveryError(
            f"출력 파일이 이미 존재합니다. 덮어쓰려면 --overwrite를 명시하세요: {path}"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=OUTPUT_HEADERS)
        writer.writeheader()
        writer.writerows(rows)


def discover(
    *,
    client: KakaoKeywordClient,
    config: SearchConfig,
    v2_path: Path,
    reviewed_path: Path,
    output_path: Path,
    exclusion_rules_path: Path = DEFAULT_EXCLUSION_RULES_PATH,
    discovered_at: str | None = None,
    overwrite: bool = False,
) -> tuple[list[dict[str, str]], DiscoveryStats]:
    existing_records, reviewed_status = build_existing_records(
        v2_path, reviewed_path
    )
    exclusion_rules = load_exclusion_rules(exclusion_rules_path)
    stats = DiscoveryStats()
    places = collect_places(client, config, exclusion_rules, stats)
    timestamp = discovered_at or datetime.now(timezone.utc).isoformat()
    rows = build_output_rows(
        places, existing_records, reviewed_status, timestamp, stats
    )
    write_output(output_path, rows, overwrite=overwrite)
    return rows, stats


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="카카오 키워드 장소검색으로 용산구 버거 보완 후보를 수집합니다."
    )
    parser.add_argument("--queries", type=Path, default=DEFAULT_QUERY_CONFIG_PATH)
    parser.add_argument("--v2", type=Path, default=DEFAULT_V2_PATH)
    parser.add_argument("--reviewed", type=Path, default=DEFAULT_REVIEWED_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV_PATH)
    parser.add_argument("--max-api-calls", type=int, default=MAX_PAGE * 11)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--estimate-only", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        config = load_search_config(args.queries)
        estimate = {
            "검색어 수": len(config.queries),
            "최소 예상 호출 수": config.minimum_calls,
            "공식 페이지 제한 기준 최대 호출 수": config.maximum_calls,
            "설정된 안전 호출 한도": args.max_api_calls,
        }
        print(json.dumps(estimate, ensure_ascii=False, indent=2))
        if args.estimate_only:
            return 0
        if args.max_api_calls < config.minimum_calls:
            raise DiscoveryError("안전 호출 한도가 검색어 수보다 작습니다.")
        api_key = read_kakao_api_key(args.env_file)
        client = KakaoKeywordClient(
            api_key, max_api_calls=args.max_api_calls
        )
        _, stats = discover(
            client=client,
            config=config,
            v2_path=args.v2,
            reviewed_path=args.reviewed,
            output_path=args.output,
            overwrite=args.overwrite,
        )
        print(json.dumps(stats.as_dict(args.output), ensure_ascii=False, indent=2))
        return 0
    except DiscoveryError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
