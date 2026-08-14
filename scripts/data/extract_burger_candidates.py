#!/usr/bin/env python3
"""Extract burger-store candidates from SEMAS commercial-area CSV data."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Mapping, Sequence


REQUIRED_HEADERS = (
    "상가업소번호",
    "상호명",
    "지점명",
    "상권업종대분류명",
    "상권업종중분류명",
    "상권업종소분류명",
    "시도명",
    "시군구명",
    "도로명주소",
    "경도",
    "위도",
)

OUTPUT_HEADERS = (
    "candidateId",
    "sourceStoreId",
    "name",
    "branchName",
    "address",
    "latitude",
    "longitude",
    "categoryLarge",
    "categoryMedium",
    "categorySmall",
    "candidateReason",
    "source",
    "sourceAsOf",
    "verificationStatus",
    "verifiedAt",
    "verificationNote",
    "burgerStyle",
    "exclusionReason",
)

CATEGORY_KEYWORDS = ("버거", "햄버거", "수제버거")
LEGACY_CATEGORY_KEYWORDS = ("패스트푸드",)
NAME_KEYWORDS = ("버거", "햄버거", "burger", "hamburger")
SOURCE_NAME = "semas_commercial_area"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BRAND_ALIASES_PATH = (
    PROJECT_ROOT / "data" / "config" / "burger_brand_aliases.json"
)
DEFAULT_EXCLUSION_RULES_PATH = (
    PROJECT_ROOT / "data" / "config" / "burger_exclusion_rules.json"
)
SEOUL_REVIEW_BOUNDS = {
    "latitude_min": 37.4,
    "latitude_max": 37.8,
    "longitude_min": 126.7,
    "longitude_max": 127.3,
}


class HeaderValidationError(ValueError):
    """Raised when the input CSV does not expose the documented schema."""

    def __init__(self, missing: Sequence[str], actual: Sequence[str]) -> None:
        self.missing = tuple(missing)
        self.actual = tuple(actual)
        super().__init__(
            "필수 CSV 헤더가 누락되었습니다. "
            f"누락: {', '.join(self.missing)}. "
            f"실제 헤더: {', '.join(self.actual) if self.actual else '(없음)'}"
        )


@dataclass
class ExtractionStats:
    total_input_rows: int = 0
    sido_rows: int = 0
    sigungu_rows: int = 0
    total_candidates: int = 0
    reason_counts: Counter[str] = field(default_factory=Counter)
    missing_required_rows: int = 0
    invalid_coordinate_rows: int = 0
    duplicate_or_suspected_rows: int = 0
    excluded_rows: int = 0
    excluded_reasons: Counter[str] = field(default_factory=Counter)
    screening_flag_counts: Counter[str] = field(default_factory=Counter)
    pending_rows: int = 0
    needs_recheck_rows: int = 0
    output_rows: int = 0

    def as_dict(self, output_path: Path) -> dict[str, object]:
        return {
            "전체 입력 행 수": self.total_input_rows,
            "시도 일치 행 수": self.sido_rows,
            "시군구 일치 행 수": self.sigungu_rows,
            "전체 후보 수": self.total_candidates,
            "category 후보 수": self.reason_counts["category"],
            "name 후보 수": self.reason_counts["name"],
            "category_and_name 후보 수": self.reason_counts[
                "category_and_name"
            ],
            "후보 근거별 수": dict(sorted(self.reason_counts.items())),
            "제외 규칙별 수": dict(sorted(self.screening_flag_counts.items())),
            "필수값 누락 수": self.missing_required_rows,
            "잘못된 좌표 수": self.invalid_coordinate_rows,
            "중복 또는 중복 의심 수": self.duplicate_or_suspected_rows,
            "제외 수": self.excluded_rows,
            "pending 수": self.pending_rows,
            "needs_recheck 수": self.needs_recheck_rows,
            "최종 출력 행 수": self.output_rows,
            "최종 출력 경로": str(output_path.resolve()),
        }


def normalize_for_comparison(value: str | None) -> str:
    """Normalize only for matching and duplicate comparison."""
    normalized = unicodedata.normalize("NFKC", value or "").lower()
    return re.sub(r"\s+", " ", normalized).strip()


def normalize_name_for_matching(value: str | None) -> str:
    """Normalize limited presentation differences for exact name matching."""
    normalized = normalize_for_comparison(value)
    return re.sub(r"[\s\-‐‑‒–—―()（）]", "", normalized)


def contains_keyword(
    value: str, keywords: Iterable[str], *, normalize_name: bool = False
) -> bool:
    normalizer = (
        normalize_name_for_matching if normalize_name else normalize_for_comparison
    )
    normalized = normalizer(value)
    return any(normalizer(keyword) in normalized for keyword in keywords)


def raw_value(row: Mapping[str, str | None], field_name: str) -> str:
    return row.get(field_name) or ""


def candidate_reason(
    row: Mapping[str, str | None], brand_aliases: frozenset[str] = frozenset()
) -> str | None:
    category_text = " ".join(
        (
            raw_value(row, "상권업종대분류명"),
            raw_value(row, "상권업종중분류명"),
            raw_value(row, "상권업종소분류명"),
        )
    )
    name_text = " ".join(
        (raw_value(row, "상호명"), raw_value(row, "지점명"))
    )
    category_small = normalize_for_comparison(
        raw_value(row, "상권업종소분류명")
    )
    category_match = (
        category_small == "버거"
        or contains_keyword(category_text, CATEGORY_KEYWORDS)
        or contains_keyword(category_text, LEGACY_CATEGORY_KEYWORDS)
    )
    name_match = contains_keyword(
        name_text, NAME_KEYWORDS, normalize_name=True
    )
    normalized_store_name = normalize_name_for_matching(
        raw_value(row, "상호명")
    )
    alias_match = normalized_store_name in brand_aliases

    reasons = {
        (True, False, False): "category",
        (False, True, False): "name",
        (True, True, False): "category_and_name",
        (False, False, True): "brand_alias",
        (True, False, True): "category_and_alias",
        (False, True, True): "name_and_alias",
        (True, True, True): "category_name_and_alias",
    }
    return reasons.get((category_match, name_match, alias_match))


def load_brand_aliases(path: Path) -> frozenset[str]:
    data = load_json_config(path)
    brands = data.get("brands")
    if not isinstance(brands, list):
        raise ValueError(f"브랜드 별칭 설정의 brands가 목록이 아닙니다: {path}")

    aliases: set[str] = set()
    for brand in brands:
        if not isinstance(brand, dict) or not isinstance(brand.get("aliases"), list):
            raise ValueError(f"브랜드 별칭 항목 형식이 올바르지 않습니다: {path}")
        aliases.update(
            normalized
            for alias in brand["aliases"]
            if isinstance(alias, str)
            and (normalized := normalize_name_for_matching(alias))
        )
    return frozenset(aliases)


def load_exclusion_rules(path: Path) -> tuple[dict[str, object], ...]:
    data = load_json_config(path)
    rules = data.get("rules")
    if not isinstance(rules, list):
        raise ValueError(f"제외 규칙 설정의 rules가 목록이 아닙니다: {path}")

    validated: list[dict[str, object]] = []
    for rule in rules:
        if (
            not isinstance(rule, dict)
            or not isinstance(rule.get("id"), str)
            or not isinstance(rule.get("type"), str)
            or rule.get("matchMode")
            not in {"exact", "exact_or_prefix", "contains"}
            or not isinstance(rule.get("aliases"), list)
            or not all(isinstance(alias, str) for alias in rule["aliases"])
            or not isinstance(rule.get("categoryKeywords", []), list)
            or not all(
                isinstance(keyword, str)
                for keyword in rule.get("categoryKeywords", [])
            )
        ):
            raise ValueError(f"제외 규칙 항목 형식이 올바르지 않습니다: {path}")
        validated.append(rule)
    return tuple(validated)


def load_json_config(path: Path) -> dict[str, object]:
    try:
        with path.open("r", encoding="utf-8-sig") as config_file:
            data = json.load(config_file)
    except OSError as error:
        raise OSError(f"설정 파일을 열 수 없습니다: {path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"설정 파일이 올바른 JSON이 아닙니다: {path}") from error
    if not isinstance(data, dict):
        raise ValueError(f"설정 파일 최상위 값은 객체여야 합니다: {path}")
    return data


def match_exclusion_rules(
    row: Mapping[str, str | None], rules: Sequence[dict[str, object]]
) -> tuple[str, ...]:
    normalized_name = normalize_name_for_matching(raw_value(row, "상호명"))
    category_text = " ".join(
        (
            raw_value(row, "상권업종대분류명"),
            raw_value(row, "상권업종중분류명"),
            raw_value(row, "상권업종소분류명"),
            raw_value(row, "sourceCategory"),
        )
    )
    matches: list[str] = []
    for rule in rules:
        mode = str(rule["matchMode"])
        normalized_aliases = (
            normalize_name_for_matching(str(alias)) for alias in rule["aliases"]
        )
        matched = any(
            normalized_name == alias
            or (mode == "exact_or_prefix" and normalized_name.startswith(alias))
            or (mode == "contains" and alias in normalized_name)
            for alias in normalized_aliases
            if alias
        )
        category_matched = contains_keyword(
            category_text,
            (
                str(keyword)
                for keyword in rule.get("categoryKeywords", [])
            ),
        )
        if matched or category_matched:
            matches.append(str(rule["id"]))
    return tuple(matches)


def validate_headers(fieldnames: Sequence[str] | None) -> None:
    actual = tuple(fieldnames or ())
    missing = [header for header in REQUIRED_HEADERS if header not in actual]
    if missing:
        raise HeaderValidationError(missing, actual)


def coordinate_notes(latitude: str, longitude: str) -> tuple[list[str], bool]:
    notes: list[str] = []
    try:
        parsed_latitude = float(latitude)
        parsed_longitude = float(longitude)
        if not math.isfinite(parsed_latitude) or not math.isfinite(parsed_longitude):
            raise ValueError
    except (TypeError, ValueError):
        return ["invalid_coordinates_not_numeric"], True

    if not -90 <= parsed_latitude <= 90:
        notes.append("latitude_out_of_range")
    if not -180 <= parsed_longitude <= 180:
        notes.append("longitude_out_of_range")
    if parsed_latitude == 0 and parsed_longitude == 0:
        notes.append("coordinates_zero_zero")

    invalid = bool(notes)
    if not invalid and not (
        SEOUL_REVIEW_BOUNDS["latitude_min"]
        <= parsed_latitude
        <= SEOUL_REVIEW_BOUNDS["latitude_max"]
        and SEOUL_REVIEW_BOUNDS["longitude_min"]
        <= parsed_longitude
        <= SEOUL_REVIEW_BOUNDS["longitude_max"]
    ):
        notes.append("coordinates_outside_seoul_review_bounds")

    return notes, invalid


def missing_required_fields(row: Mapping[str, str | None]) -> list[str]:
    category_values = (
        raw_value(row, "상권업종대분류명"),
        raw_value(row, "상권업종중분류명"),
        raw_value(row, "상권업종소분류명"),
    )
    checks = {
        "sourceStoreId": raw_value(row, "상가업소번호"),
        "name": raw_value(row, "상호명"),
        "address": raw_value(row, "도로명주소"),
        "latitude": raw_value(row, "위도"),
        "longitude": raw_value(row, "경도"),
        "category": "".join(category_values),
    }
    return [
        field_name
        for field_name, value in checks.items()
        if not normalize_for_comparison(value)
    ]


def append_note(candidate: dict[str, str], note: str) -> None:
    notes = [item for item in candidate["verificationNote"].split(";") if item]
    if note not in notes:
        notes.append(note)
    candidate["verificationNote"] = ";".join(notes)
    candidate["verificationStatus"] = "needs_recheck"


def build_candidate(
    row: Mapping[str, str | None], reason: str, source_as_of: str
) -> dict[str, str]:
    source_store_id = raw_value(row, "상가업소번호")
    return {
        "candidateId": f"semas_{source_store_id}",
        "sourceStoreId": source_store_id,
        "name": raw_value(row, "상호명"),
        "branchName": raw_value(row, "지점명"),
        "address": raw_value(row, "도로명주소"),
        "latitude": raw_value(row, "위도"),
        "longitude": raw_value(row, "경도"),
        "categoryLarge": raw_value(row, "상권업종대분류명"),
        "categoryMedium": raw_value(row, "상권업종중분류명"),
        "categorySmall": raw_value(row, "상권업종소분류명"),
        "candidateReason": reason,
        "source": SOURCE_NAME,
        "sourceAsOf": source_as_of,
        "verificationStatus": "pending",
        "verifiedAt": "",
        "verificationNote": "",
        "burgerStyle": "미분류",
        "exclusionReason": "",
    }


def mark_duplicates(candidates: list[dict[str, str]]) -> int:
    source_groups: defaultdict[str, list[int]] = defaultdict(list)
    candidate_groups: defaultdict[str, list[int]] = defaultdict(list)
    name_address_groups: defaultdict[tuple[str, str], list[int]] = defaultdict(list)

    for index, candidate in enumerate(candidates):
        source_groups[candidate["sourceStoreId"]].append(index)
        candidate_groups[candidate["candidateId"]].append(index)
        duplicate_key = (
            normalize_for_comparison(candidate["name"]),
            normalize_for_comparison(candidate["address"]),
        )
        name_address_groups[duplicate_key].append(index)

    duplicate_indexes: set[int] = set()
    for groups, note in (
        (source_groups, "duplicate_source_store_id"),
        (candidate_groups, "duplicate_candidate_id"),
        (name_address_groups, "suspected_duplicate_name_address"),
    ):
        for indexes in groups.values():
            if len(indexes) < 2:
                continue
            duplicate_indexes.update(indexes)
            for index in indexes:
                append_note(candidates[index], note)

    return len(duplicate_indexes)


def extract_candidates(
    input_path: Path,
    output_path: Path,
    source_as_of: str,
    sido: str = "서울특별시",
    sigungu: str = "용산구",
    brand_aliases_path: Path = DEFAULT_BRAND_ALIASES_PATH,
    exclusion_rules_path: Path = DEFAULT_EXCLUSION_RULES_PATH,
) -> ExtractionStats:
    stats = ExtractionStats()
    candidates: list[dict[str, str]] = []
    brand_aliases = load_brand_aliases(brand_aliases_path)
    exclusion_rules = load_exclusion_rules(exclusion_rules_path)

    try:
        input_file = input_path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise OSError(f"입력 CSV를 열 수 없습니다: {input_path}") from error

    try:
        with input_file:
            reader = csv.DictReader(input_file)
            validate_headers(reader.fieldnames)

            for row in reader:
                stats.total_input_rows += 1
                if normalize_for_comparison(
                    raw_value(row, "시도명")
                ) != normalize_for_comparison(sido):
                    continue
                stats.sido_rows += 1

                if normalize_for_comparison(
                    raw_value(row, "시군구명")
                ) != normalize_for_comparison(sigungu):
                    continue
                stats.sigungu_rows += 1

                reason = candidate_reason(row, brand_aliases)
                if reason is None:
                    continue

                stats.total_candidates += 1
                stats.reason_counts[reason] += 1
                missing = missing_required_fields(row)
                if missing:
                    stats.missing_required_rows += 1

                if "sourceStoreId" in missing:
                    stats.excluded_rows += 1
                    stats.excluded_reasons["missing_source_store_id"] += 1
                    continue

                candidate = build_candidate(row, reason, source_as_of)
                if missing:
                    append_note(
                        candidate,
                        "missing_required:" + ",".join(sorted(missing)),
                    )

                coordinate_issues, invalid_coordinate = coordinate_notes(
                    raw_value(row, "위도"), raw_value(row, "경도")
                )
                if invalid_coordinate:
                    stats.invalid_coordinate_rows += 1
                for issue in coordinate_issues:
                    append_note(candidate, issue)

                exclusion_reasons = match_exclusion_rules(row, exclusion_rules)
                if exclusion_reasons:
                    candidate["exclusionReason"] = ";".join(exclusion_reasons)
                    for exclusion_reason in exclusion_reasons:
                        stats.screening_flag_counts[exclusion_reason] += 1
                        append_note(
                            candidate,
                            f"exclusion_rule:{exclusion_reason}",
                        )

                candidates.append(candidate)
    except UnicodeDecodeError as error:
        raise ValueError(
            "입력 CSV를 UTF-8 또는 UTF-8-SIG로 읽을 수 없습니다. "
            "원본 인코딩을 확인하고 UTF-8로 변환한 뒤 다시 실행하세요."
        ) from error

    stats.duplicate_or_suspected_rows = mark_duplicates(candidates)
    candidates.sort(
        key=lambda candidate: (
            candidate["candidateId"],
            candidate["name"],
            candidate["address"],
        )
    )

    stats.pending_rows = sum(
        candidate["verificationStatus"] == "pending" for candidate in candidates
    )
    stats.needs_recheck_rows = sum(
        candidate["verificationStatus"] == "needs_recheck"
        for candidate in candidates
    )
    stats.output_rows = len(candidates)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=OUTPUT_HEADERS)
        writer.writeheader()
        writer.writerows(candidates)

    return stats


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="공공 상가정보 CSV에서 버거 매장 검수 후보를 추출합니다."
    )
    parser.add_argument("--input", required=True, type=Path, help="원본 CSV 경로")
    parser.add_argument("--output", required=True, type=Path, help="후보 CSV 경로")
    parser.add_argument(
        "--source-as-of",
        required=True,
        help="원본 데이터 기준일(추측하지 말고 원본에서 확인)",
    )
    parser.add_argument("--sido", default="서울특별시", help="시도명 필터")
    parser.add_argument("--sigungu", default="용산구", help="시군구명 필터")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if not args.source_as_of.strip():
        print("오류: --source-as-of 값은 비어 있을 수 없습니다.", file=sys.stderr)
        return 2

    try:
        stats = extract_candidates(
            input_path=args.input,
            output_path=args.output,
            source_as_of=args.source_as_of,
            sido=args.sido,
            sigungu=args.sigungu,
        )
    except (HeaderValidationError, OSError, ValueError) as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2

    print(json.dumps(stats.as_dict(args.output), ensure_ascii=False, indent=2))
    if stats.excluded_reasons:
        print(
            "제외 사유: "
            + json.dumps(stats.excluded_reasons, ensure_ascii=False, sort_keys=True)
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
