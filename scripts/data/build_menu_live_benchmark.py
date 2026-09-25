"""Summarize reviewed live menu-source probes without fetching or publishing data.

Input observations come from a separately recorded search/browser session. This
module deliberately has no HTTP client and never writes to Supabase.
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
from collections import Counter
from pathlib import Path
from urllib.parse import parse_qsl, urlparse


QUERY_SUFFIXES = ("메뉴", "가격", "주문", "공식", "instagram", "burger menu", "order")
SOURCE_TYPES = {
    "official_website",
    "official_store_page",
    "official_brand_page",
    "official_social",
    "official_order",
    "business_profile",
    "delivery_platform",
    "reservation_platform",
    "kakao_place",
    "naver_place",
    "third_party_review",
    "blog",
    "unknown",
}
SOURCE_TIERS = {"A", "B", "C"}
MATCHES = {"EXACT_MATCH", "LIKELY_MATCH", "AMBIGUOUS", "MISMATCH", "UNKNOWN"}
ACCESS = {"ACCESSIBLE", "BLOCKED_SOURCE", "FETCH_ERROR", "NOT_FETCHED"}
CURRENTNESS = {"HIGH", "MEDIUM", "LOW", "UNKNOWN"}
PRICE_CONTEXTS = {"dine_in", "pickup", "delivery", "order_channel", "unknown"}
SENSITIVE_QUERY_KEYS = {
    "access_token",
    "apikey",
    "api_key",
    "key",
    "password",
    "secret",
    "token",
}
STORE_FIELDS = (
    "store_id",
    "store_name",
    "address",
    "burger_style",
    "stratum",
    "searches_executed",
    "search_cap_exceeded",
    "sources_found",
    "tier_a_found",
    "tier_b_found",
    "exact_matches",
    "menu_extracted",
    "price_extracted",
    "signature_extracted",
    "blocked_sources",
    "ambiguous_identity",
    "automation_class",
    "rationale",
)
SOURCE_FIELDS = (
    "store_id",
    "store_name",
    "source_url",
    "source_type",
    "source_tier",
    "store_match",
    "access_status",
    "http_status",
    "currentness",
    "observed_at",
    "retrieved_at",
    "query_used",
    "menu_extracted",
    "price_extracted",
    "signature_extracted",
    "notes",
)
CANDIDATE_FIELDS = (
    "store_id",
    "store_name",
    "menu_name",
    "displayed_price",
    "price_krw",
    "price_context",
    "source_url",
    "evidence_grade",
    "suggested_decision",
    "signature_wording",
    "extraction_method",
    "observed_at",
    "retrieved_at",
)


def search_queries(store: dict) -> list[str]:
    name = store["store_name"].strip()
    district = store.get("district", "").strip()
    queries = [f"{name} {suffix}" for suffix in QUERY_SUFFIXES]
    if district:
        queries.insert(4, f"{name} {district} 메뉴")
    return list(dict.fromkeys(queries))


def adaptive_search(
    store: dict, search, inspect, max_queries: int = 8
) -> tuple[list[str], list[dict]]:
    """Dependency-injected search loop; no real transport is shipped here."""
    executed: list[str] = []
    inspected: list[dict] = []
    for query in search_queries(store)[:max_queries]:
        executed.append(query)
        for hit in search(query):
            result = inspect(hit)
            inspected.append(result)
            if (
                result.get("source_tier") in {"A", "B"}
                and result.get("store_match") == "EXACT_MATCH"
                and result.get("access_status") == "ACCESSIBLE"
                and result.get("currentness") in {"HIGH", "MEDIUM"}
                and result.get("menu_extracted", False)
            ):
                return executed, inspected
    return executed, inspected


def validate_url(url: str) -> None:
    parsed = urlparse(url)
    query_keys = {
        key.casefold() for key, _ in parse_qsl(parsed.query, keep_blank_values=True)
    }
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.netloc
        or parsed.username
        or parsed.password
        or query_keys & SENSITIVE_QUERY_KEYS
    ):
        raise ValueError("source URL must be public HTTP(S) without credentials")


def has_exact_price(candidate: dict) -> bool:
    value = candidate.get("price_krw")
    return type(value) is int and value >= 0


def classify_store(sources: list[dict]) -> tuple[str, str]:
    if not sources:
        return "INSUFFICIENT_EVIDENCE", "no source found in bounded search"
    accessible = [s for s in sources if s["access_status"] == "ACCESSIBLE"]
    if not accessible:
        if any(s["access_status"] == "BLOCKED_SOURCE" for s in sources):
            return "SOURCE_BLOCKED", "no accessible source; at least one blocked"
        return "INSUFFICIENT_EVIDENCE", "sources not retrieved or failed"
    eligible = [
        s
        for s in accessible
        if s["source_tier"] in {"A", "B"}
        and s["store_match"] == "EXACT_MATCH"
        and s["currentness"] in {"HIGH", "MEDIUM"}
    ]
    if not eligible:
        return (
            "HUMAN_REVIEW_REQUIRED",
            "accessible source lacks exact current A/B evidence",
        )
    if any(
        s["source_tier"] == "A"
        and s["currentness"] == "HIGH"
        and any(
            c.get("menu_name")
            and has_exact_price(c)
            and c.get("price_context") == "dine_in"
            for c in s.get("candidates", [])
        )
        for s in eligible
    ):
        return (
            "FULLY_AUTOMATABLE",
            "current official names and dine-in prices extractable; publish still needs approval",
        )
    if any(s.get("candidates") for s in eligible):
        return (
            "PARTIALLY_AUTOMATABLE",
            "menu candidates extracted; price or approval needs review",
        )
    return "HUMAN_REVIEW_REQUIRED", "source found but menu fields not extracted"


def build_rows(payload: dict) -> tuple[list[dict], list[dict], list[dict], dict]:
    stores_out: list[dict] = []
    sources_out: list[dict] = []
    candidates_out: list[dict] = []
    seen_ids: set[str] = set()
    for store in payload["stores"]:
        store_id = store["store_id"]
        if store_id in seen_ids:
            raise ValueError("duplicate store ID")
        seen_ids.add(store_id)
        sources = store.get("sources", [])
        searches = store.get("searches", [])
        extra_searches = store.get("additional_searches_after_cap", [])
        if len(searches) > 8:
            raise ValueError("more than eight searches recorded for one store")
        for source in sources:
            validate_url(source["source_url"])
            for field, allowed in (
                ("source_type", SOURCE_TYPES),
                ("source_tier", SOURCE_TIERS),
                ("store_match", MATCHES),
                ("access_status", ACCESS),
                ("currentness", CURRENTNESS),
            ):
                if source.get(field) not in allowed:
                    raise ValueError(f"invalid {field}")
            if source["access_status"] != "ACCESSIBLE" and (
                source.get("observed_at") or source.get("retrieved_at")
            ):
                raise ValueError(
                    "inaccessible source cannot have observed/retrieved dates"
                )
            for candidate in source.get("candidates", []):
                if source["access_status"] != "ACCESSIBLE":
                    raise ValueError("cannot extract menu from inaccessible source")
                if source["store_match"] in {"AMBIGUOUS", "MISMATCH", "UNKNOWN"}:
                    raise ValueError("cannot link menu to unverified store identity")
                if not candidate.get("menu_name", "").strip():
                    raise ValueError("menu candidate needs an observed name")
                if candidate.get("price_context", "unknown") not in PRICE_CONTEXTS:
                    raise ValueError("invalid price context")
                if candidate.get("price_krw") not in {None, ""} and not has_exact_price(
                    candidate
                ):
                    raise ValueError("price_krw must be an exact nonnegative integer")
                if source["source_tier"] == "C" and candidate.get(
                    "suggested_decision", "NEEDS_REVIEW"
                ).startswith("READY"):
                    raise ValueError("Tier C cannot suggest publication readiness")
                candidates_out.append(
                    {
                        "store_id": store_id,
                        "store_name": store["store_name"],
                        "menu_name": candidate.get("menu_name", ""),
                        "displayed_price": candidate.get("displayed_price", ""),
                        "price_krw": candidate.get("price_krw", ""),
                        "price_context": candidate.get("price_context", "unknown"),
                        "source_url": source["source_url"],
                        "evidence_grade": candidate.get(
                            "evidence_grade", "NEEDS_REVIEW"
                        ),
                        "suggested_decision": candidate.get(
                            "suggested_decision", "NEEDS_REVIEW"
                        ),
                        "signature_wording": candidate.get("signature_wording", ""),
                        "extraction_method": candidate.get("extraction_method", ""),
                        "observed_at": source.get("observed_at", ""),
                        "retrieved_at": source.get("retrieved_at", ""),
                    }
                )
            sources_out.append(
                {
                    "store_id": store_id,
                    "store_name": store["store_name"],
                    **{
                        field: source.get(field, "")
                        for field in SOURCE_FIELDS
                        if field
                        not in {
                            "store_id",
                            "store_name",
                            "menu_extracted",
                            "price_extracted",
                            "signature_extracted",
                        }
                    },
                    "menu_extracted": bool(source.get("candidates")),
                    "price_extracted": any(
                        has_exact_price(c) for c in source.get("candidates", [])
                    ),
                    "signature_extracted": any(
                        bool(c.get("signature_wording"))
                        for c in source.get("candidates", [])
                    ),
                }
            )
        automation_class, rationale = classify_store(sources)
        stores_out.append(
            {
                "store_id": store_id,
                "store_name": store["store_name"],
                "address": store["address"],
                "burger_style": store.get("burger_style", ""),
                "stratum": store.get("stratum", ""),
                "searches_executed": len(searches) + len(extra_searches),
                "search_cap_exceeded": bool(extra_searches),
                "sources_found": len(sources),
                "tier_a_found": sum(s["source_tier"] == "A" for s in sources),
                "tier_b_found": sum(s["source_tier"] == "B" for s in sources),
                "exact_matches": sum(
                    s["store_match"] == "EXACT_MATCH" for s in sources
                ),
                "menu_extracted": any(s.get("candidates") for s in sources),
                "price_extracted": any(
                    has_exact_price(c) for s in sources for c in s.get("candidates", [])
                ),
                "signature_extracted": any(
                    c.get("signature_wording")
                    for s in sources
                    for c in s.get("candidates", [])
                ),
                "blocked_sources": sum(
                    s["access_status"] == "BLOCKED_SOURCE" for s in sources
                ),
                "ambiguous_identity": sum(
                    s["store_match"] == "AMBIGUOUS" for s in sources
                ),
                "automation_class": automation_class,
                "rationale": rationale,
            }
        )
    counts = Counter(row["automation_class"] for row in stores_out)
    search_counts = [row["searches_executed"] for row in stores_out]
    metrics = {
        "total_stores": len(stores_out),
        "stores_with_any_source": sum(row["sources_found"] > 0 for row in stores_out),
        "stores_with_tier_a": sum(row["tier_a_found"] > 0 for row in stores_out),
        "stores_with_tier_b": sum(row["tier_b_found"] > 0 for row in stores_out),
        "stores_with_exact_match": sum(row["exact_matches"] > 0 for row in stores_out),
        "stores_with_menu_extraction": sum(row["menu_extracted"] for row in stores_out),
        "stores_with_price_extraction": sum(
            row["price_extracted"] for row in stores_out
        ),
        "stores_with_signature_extraction": sum(
            row["signature_extracted"] for row in stores_out
        ),
        "blocked_source_count": sum(row["blocked_sources"] for row in stores_out),
        "ambiguous_identity_count": sum(
            row["ambiguous_identity"] for row in stores_out
        ),
        "no_source_stores": sum(row["sources_found"] == 0 for row in stores_out),
        "searches_executed": sum(search_counts),
        "stores_exceeding_search_cap": sum(
            row["search_cap_exceeded"] for row in stores_out
        ),
        "searches_per_store_mean": round(statistics.mean(search_counts), 2)
        if search_counts
        else 0,
        "searches_per_store_median": statistics.median(search_counts)
        if search_counts
        else 0,
        "automation_classes": dict(counts),
    }
    return stores_out, sources_out, candidates_out, metrics


def write_csv(path: Path, fields: tuple[str, ...], rows: list[dict]) -> None:
    if path.exists():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--stores-output", required=True, type=Path)
    parser.add_argument("--sources-output", required=True, type=Path)
    parser.add_argument("--candidates-output", required=True, type=Path)
    parser.add_argument("--metrics-output", required=True, type=Path)
    args = parser.parse_args()
    outputs = (
        args.stores_output,
        args.sources_output,
        args.candidates_output,
        args.metrics_output,
    )
    if any(path.exists() for path in outputs):
        parser.error("output exists; use new versioned paths")
    payload = json.loads(args.input.read_text(encoding="utf-8"))
    stores, sources, candidates, metrics = build_rows(payload)
    write_csv(args.stores_output, STORE_FIELDS, stores)
    write_csv(args.sources_output, SOURCE_FIELDS, sources)
    write_csv(args.candidates_output, CANDIDATE_FIELDS, candidates)
    args.metrics_output.write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(metrics, ensure_ascii=False))


if __name__ == "__main__":
    main()
