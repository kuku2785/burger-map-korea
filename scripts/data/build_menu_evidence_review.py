"""Build an offline, non-publishing menu evidence review from curated observations.

Discovery and extraction are separate upstream steps. This script never fetches a
URL or connects to Supabase; it preserves their provenance in review artifacts.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import unicodedata
from pathlib import Path
from urllib.parse import parse_qsl, urlparse


QUERY_SUFFIXES = ("메뉴", "가격", "주문", "공식", "burger menu", "instagram", "order")
SOURCE_TIERS = {
    "official_website": "A",
    "official_store_page": "A",
    "official_brand_page": "A",
    "official_social": "A",
    "official_order": "A",
    "business_profile": "B",
    "delivery_platform": "B",
    "reservation_platform": "B",
    "kakao_place": "C",
    "naver_place": "C",
    "third_party_review": "C",
    "blog": "C",
    "unknown": "C",
}
KNOWN_PLATFORM_TYPES = {
    "www.shuttledelivery.co.kr": "delivery_platform",
    "www.daangn.com": "business_profile",
}
SENSITIVE_QUERY_KEYS = {
    "access_token",
    "apikey",
    "api_key",
    "key",
    "password",
    "secret",
    "token",
}
FIELDS = (
    "store_id",
    "store_name",
    "store_address",
    "menu_name_raw",
    "menu_name_normalized",
    "observed_price_raw",
    "observed_price_krw",
    "publish_price_krw",
    "price_context",
    "currency",
    "is_signature_candidate",
    "source_url",
    "source_domain",
    "source_type",
    "source_tier",
    "source_store_match",
    "checked_at",
    "extraction_method",
    "evidence_grade",
    "decision_suggestion",
    "decision_reason",
    "evidence_notes",
    "duplicate_of",
    "human_approved",
)
DISCOVERY_FIELDS = (
    "store_id",
    "store_name",
    "source_url",
    "source_domain",
    "source_type",
    "title",
    "discovered_at",
    "discovery_query",
    "candidate_score",
    "source_tier",
    "source_store_match",
    "access_status",
)


def normalize_name(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    value = re.sub(r"[^\w\s]", " ", value, flags=re.UNICODE)
    return " ".join(value.split())


def parse_price(value: str) -> int | None:
    """Accept only explicit full KRW amounts, never shorthand or starting prices."""
    value = value.strip()
    if not re.fullmatch(r"(?:0|[1-9]\d{0,2}(?:,\d{3})+|[1-9]\d*)\s*원", value):
        return None
    return int(value.removesuffix("원").replace(",", "").strip())


def observed_price_krw(menu: dict) -> int | None:
    raw_price = menu.get("price_raw", "")
    if menu.get("price_record_kind") == "prior_csv_numeric_krw":
        # A prior review preserved a KRW integer but not the page's exact text.
        return int(raw_price) if re.fullmatch(r"(?:0|[1-9]\d*)", raw_price) else None
    return parse_price(raw_price)


def identity_match(store: dict, source: dict) -> str:
    name = normalize_name(source.get("source_store_name", ""))
    address = normalize_name(source.get("source_address", ""))
    store_name = normalize_name(store["name"])
    store_address = normalize_name(store["address"])
    if name == store_name and address == store_address:
        return "EXACT_MATCH"
    if address and address != store_address:
        return "MISMATCH"
    if name and name != store_name:
        return "AMBIGUOUS"
    if name or address:
        return "LIKELY_MATCH"
    return "AMBIGUOUS"


def search_queries(store: dict) -> list[str]:
    name = store["name"].strip()
    address = store["address"].strip()
    return [f"{name} {suffix}" for suffix in QUERY_SUFFIXES] + [f"{name} {address} 메뉴"]


def classify_source(source: dict) -> tuple[str, str]:
    domain = urlparse(source["url"]).netloc.lower()
    source_type = KNOWN_PLATFORM_TYPES.get(domain, source.get("source_type", "unknown"))
    if source_type not in SOURCE_TIERS:
        source_type = "unknown"
    if SOURCE_TIERS[source_type] == "A" and not source.get("ownership_verified", False):
        return "unknown", "C"
    return source_type, SOURCE_TIERS[source_type]


def grade_candidate(
    tier: str, match: str, source: dict, menu: dict, price: int | None
) -> tuple[str, str, str]:
    if match == "MISMATCH":
        return "X", "REJECT", "source address differs from target store"
    if source.get("access_status") == "BLOCKED_SOURCE":
        return "X", "BLOCKED_SOURCE", "source could not be directly accessed"
    if match != "EXACT_MATCH":
        return "B2", "NEEDS_REVIEW", "store identity is not exact"
    if not menu.get("name_raw", "").strip():
        return "X", "REJECT", "menu name is missing"
    if tier == "C":
        return "C", "NEEDS_REVIEW", "discovery or corroboration source only"
    if tier == "B":
        return "B1", "NEEDS_REVIEW", "business/channel source needs human confirmation"
    if not source.get("current_menu", False):
        return "A3", "NEEDS_REVIEW", "source does not establish a current menu"
    if (
        price is not None
        and menu.get("price_context") == "dine_in"
        and menu.get("price_record_kind") != "prior_csv_numeric_krw"
    ):
        return "A1", "READY_WITH_PRICE", "current official dine-in price"
    return (
        "A2",
        "READY_WITHOUT_PRICE",
        "current official menu; public price unconfirmed",
    )


def build_review(payload: dict) -> tuple[list[dict], list[dict]]:
    discovery: list[dict] = []
    review: list[dict] = []
    seen: dict[tuple[str, str], str] = {}
    for store in payload["stores"]:
        queries = search_queries(store)
        for source in store["sources"]:
            parsed_url = urlparse(source["url"])
            query_keys = {
                key.casefold()
                for key, _ in parse_qsl(parsed_url.query, keep_blank_values=True)
            }
            if (
                parsed_url.scheme not in {"http", "https"}
                or not parsed_url.netloc
                or parsed_url.username
                or parsed_url.password
                or query_keys & SENSITIVE_QUERY_KEYS
            ):
                raise ValueError(
                    "source URL must be public HTTP(S) without credentials"
                )
            source_type, tier = classify_source(source)
            match = identity_match(store, source)
            discovery.append(
                {
                    "store_id": store["id"],
                    "store_name": store["name"],
                    "source_url": source["url"],
                    "source_domain": parsed_url.netloc.lower(),
                    "source_type": source_type,
                    "title": source.get("title", ""),
                    "discovered_at": source["checked_at"],
                    "discovery_query": source.get("discovery_query", queries[0]),
                    "candidate_score": 1 if match == "EXACT_MATCH" else 0,
                    "source_tier": tier,
                    "source_store_match": match,
                    "access_status": source.get("access_status", "OBSERVED"),
                }
            )
            for menu in source.get("menus", []):
                name = menu.get("name_raw", "").strip()
                normalized = normalize_name(name)
                raw_price = menu.get("price_raw", "")
                observed_price = observed_price_krw(menu)
                context = menu.get("price_context", "unknown")
                if context not in {
                    "dine_in",
                    "pickup",
                    "delivery",
                    "order_channel",
                    "unknown",
                }:
                    raise ValueError("unknown price context")
                grade, decision, reason = grade_candidate(
                    tier, match, source, menu, observed_price
                )
                key = (store["id"], normalized)
                duplicate_of = seen.get(key, "") if normalized else ""
                if duplicate_of and decision not in {"REJECT", "BLOCKED_SOURCE"}:
                    decision, reason = (
                        "NEEDS_REVIEW",
                        "duplicate menu name needs source reconciliation",
                    )
                elif normalized:
                    seen[key] = source["url"]
                public_price = (
                    observed_price if decision == "READY_WITH_PRICE" else None
                )
                review.append(
                    {
                        "store_id": store["id"],
                        "store_name": store["name"],
                        "store_address": store["address"],
                        "menu_name_raw": name,
                        "menu_name_normalized": normalized,
                        "observed_price_raw": raw_price,
                        "observed_price_krw": observed_price,
                        "publish_price_krw": public_price,
                        "price_context": context,
                        "currency": "KRW",
                        "is_signature_candidate": bool(
                            menu.get("signature_claim", False) and tier == "A"
                        ),
                        "source_url": source["url"],
                        "source_domain": parsed_url.netloc.lower(),
                        "source_type": source_type,
                        "source_tier": tier,
                        "source_store_match": match,
                        "checked_at": source["checked_at"],
                        "extraction_method": menu.get(
                            "extraction_method", "manual_observation"
                        ),
                        "evidence_grade": grade,
                        "decision_suggestion": decision,
                        "decision_reason": reason,
                        "evidence_notes": menu.get("notes", ""),
                        "duplicate_of": duplicate_of,
                        "human_approved": False,
                    }
                )
    return discovery, review


def write_csv(path: Path, fields: tuple[str, ...], rows: list[dict]) -> None:
    if path.exists():
        raise FileExistsError(f"review artifact already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--discovery-output", type=Path, required=True)
    parser.add_argument("--review-output", type=Path, required=True)
    args = parser.parse_args()
    if args.discovery_output.exists() or args.review_output.exists():
        parser.error("output exists; use new versioned paths")
    payload = json.loads(args.input.read_text(encoding="utf-8"))
    discovery, review = build_review(payload)
    write_csv(args.discovery_output, DISCOVERY_FIELDS, discovery)
    write_csv(args.review_output, FIELDS, review)
    print(
        f"stores={len(payload['stores'])} sources={len(discovery)} candidates={len(review)}"
    )


if __name__ == "__main__":
    main()
