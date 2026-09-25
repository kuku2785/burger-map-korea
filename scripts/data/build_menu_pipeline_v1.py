"""Plan a human-reviewed menu pipeline from recorded source observations.

This module has no network client, SQL generator, or production write path.
Discovery transport and extraction remain separate; its output is a review queue.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import unicodedata
from pathlib import Path
from urllib.parse import parse_qsl, urlparse


SOURCE_TIERS = {"A", "B", "C"}
MATCHES = {"EXACT_MATCH", "LIKELY_MATCH", "AMBIGUOUS", "MISMATCH", "UNKNOWN"}
CURRENTNESS = {"HIGH", "MEDIUM", "LOW", "UNKNOWN"}
ACCESS = {"ACCESSIBLE", "BLOCKED_SOURCE", "FETCH_ERROR", "NOT_FETCHED"}
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
PRIORITY_FIELDS = (
    "store_id",
    "store_name",
    "address",
    "priority",
    "priority_reason",
    "source_count",
    "strong_exact_accessible_sources",
    "menu_observations",
    "selection_status",
)
REVIEW_FIELDS = (
    "store_id",
    "store_name",
    "address",
    "row_type",
    "menu_name",
    "normalized_menu_name",
    "observed_price_krw",
    "suggested_public_price_krw",
    "price_context",
    "source_url",
    "source_type",
    "source_tier",
    "store_match_status",
    "access_status",
    "currentness",
    "source_published_at",
    "retrieved_at",
    "signature_evidence",
    "review_status",
    "decision_reason",
    "human_approved",
    "approval_ref",
    "notes",
)


def normalize_menu_name(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    value = re.sub(r"[^\w\s]", " ", value, flags=re.UNICODE)
    return " ".join(value.split())


def validate_review_url(url: str) -> None:
    parsed = urlparse(url)
    query_keys = {
        key.lower() for key, _ in parse_qsl(parsed.query, keep_blank_values=True)
    }
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.fragment
        or query_keys & SENSITIVE_QUERY_KEYS
    ):
        raise ValueError("source URL must be public and without credentials")


def search_queries(store: dict) -> list[str]:
    name = store["store_name"].strip()
    district = store.get("district", "").strip()
    queries = [
        f"{name} 메뉴",
        f"{name} 가격",
        f"{name} 주문",
        f"{name} 공식",
        f"{name} {district} 메뉴" if district else f"{name} burger menu",
        f"{name} instagram",
        f"{name} burger menu",
        f"{name} order",
    ]
    return list(dict.fromkeys(queries))


def should_stop_search(source: dict) -> bool:
    return (
        source.get("source_tier") in {"A", "B"}
        and source.get("store_match") == "EXACT_MATCH"
        and source.get("access_status") == "ACCESSIBLE"
        and any(
            candidate.get("menu_name", "").strip()
            for candidate in source.get("candidates", [])
        )
    )


def adaptive_discover(
    store: dict, search, inspect, *, target: int = 3, maximum: int = 5
):
    """Use injected transports; search at most five times and stop on useful A/B."""
    if not 1 <= target <= maximum <= 5:
        raise ValueError("v1 search budget must be 1..5")
    executed: list[str] = []
    sources: list[dict] = []
    for query in search_queries(store)[:maximum]:
        executed.append(query)
        for hit in search(query):
            source = inspect(hit)
            sources.append(source)
            if should_stop_search(source):
                return executed, sources
        if len(executed) >= target and not any(
            source.get("store_match") in {"EXACT_MATCH", "LIKELY_MATCH"}
            and source.get("access_status") != "BLOCKED_SOURCE"
            for source in sources
        ):
            break
    return executed, sources


def classify_review(source: dict, candidate: dict | None) -> tuple[str, str]:
    tier = source["source_tier"]
    match = source["store_match"]
    access = source["access_status"]
    currentness = source["currentness"]
    if (
        tier not in SOURCE_TIERS
        or match not in MATCHES
        or access not in ACCESS
        or currentness not in CURRENTNESS
    ):
        raise ValueError("invalid source classification")
    if access == "BLOCKED_SOURCE":
        return "BLOCKED_SOURCE", "confirmed access restriction; do not bypass"
    if access != "ACCESSIBLE":
        return "DEEP_REVIEW", "source retrieval did not succeed; menu absence unproven"
    if match == "MISMATCH":
        return "REJECT", "source belongs to a different store/address"
    if match != "EXACT_MATCH":
        return "DEEP_REVIEW", "store identity requires human resolution"
    if tier == "C":
        return "DEEP_REVIEW", "Tier C is discovery/corroboration only"
    if candidate is None or not candidate.get("menu_name", "").strip():
        return "DEEP_REVIEW", "no named menu observed in retrieved source"
    if currentness == "LOW":
        return "DEEP_REVIEW", "menu currentness is low"
    if tier == "A" and currentness == "HIGH":
        return (
            "AUTO_READY",
            "strong exact current source; human approval still required",
        )
    return "QUICK_REVIEW", "exact A/B menu; confirm currentness, context, and price"


def priority_for_store(store: dict) -> tuple[str, str]:
    sources = store.get("sources", [])
    if any(
        s["source_tier"] in {"A", "B"}
        and s["store_match"] == "EXACT_MATCH"
        and s["access_status"] == "ACCESSIBLE"
        for s in sources
    ):
        return "HIGH", "accessible exact A/B source"
    if any(
        s["store_match"] in {"EXACT_MATCH", "LIKELY_MATCH"}
        and s["access_status"] != "BLOCKED_SOURCE"
        for s in sources
    ):
        return "MEDIUM", "source lead exists but extraction or trust needs review"
    return "LOW", "no usable source or identity conflict"


def build_review_rows(payload: dict) -> tuple[list[dict], list[dict]]:
    priority_rows: list[dict] = []
    review_rows: list[dict] = []
    seen_ids: set[str] = set()
    for store in payload["stores"]:
        store_id = store["store_id"]
        if store_id in seen_ids:
            raise ValueError("duplicate store ID")
        seen_ids.add(store_id)
        priority, reason = priority_for_store(store)
        sources = store.get("sources", [])
        priority_rows.append(
            {
                "store_id": store_id,
                "store_name": store["store_name"],
                "address": store["address"],
                "priority": priority,
                "priority_reason": reason,
                "source_count": len(sources),
                "strong_exact_accessible_sources": sum(
                    s["source_tier"] in {"A", "B"}
                    and s["store_match"] == "EXACT_MATCH"
                    and s["access_status"] == "ACCESSIBLE"
                    for s in sources
                ),
                "menu_observations": sum(len(s.get("candidates", [])) for s in sources),
                "selection_status": "PILOT_CANDIDATE"
                if priority == "HIGH"
                else "LATER_REVIEW",
            }
        )
        for source in sources:
            validate_review_url(source["source_url"])
            candidates = source.get("candidates") or [None]
            for candidate in candidates:
                status, decision_reason = classify_review(source, candidate)
                candidate = candidate or {}
                context = candidate.get("price_context", "unknown")
                if context not in PRICE_CONTEXTS:
                    raise ValueError("invalid price context")
                observed_price = candidate.get("price_krw")
                if observed_price not in {None, ""} and (
                    type(observed_price) is not int or observed_price < 0
                ):
                    raise ValueError(
                        "observed price must be a nonnegative integer or null"
                    )
                review_rows.append(
                    {
                        "store_id": store_id,
                        "store_name": store["store_name"],
                        "address": store["address"],
                        "row_type": "MENU" if candidate else "SOURCE",
                        "menu_name": candidate.get("menu_name", ""),
                        "normalized_menu_name": normalize_menu_name(
                            candidate.get("menu_name", "")
                        ),
                        "observed_price_krw": observed_price,
                        "suggested_public_price_krw": "",  # reviewer must verify dine-in parity
                        "price_context": context,
                        "source_url": source["source_url"],
                        "source_type": source["source_type"],
                        "source_tier": source["source_tier"],
                        "store_match_status": source["store_match"],
                        "access_status": source["access_status"],
                        "currentness": source["currentness"],
                        "source_published_at": source.get("observed_at") or "",
                        "retrieved_at": source.get("retrieved_at") or "",
                        "signature_evidence": candidate.get("signature_wording", ""),
                        "review_status": status,
                        "decision_reason": decision_reason,
                        "human_approved": False,
                        "approval_ref": "",
                        "notes": source.get("notes", ""),
                    }
                )
    order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
    priority_rows.sort(key=lambda row: (order[row["priority"]], row["store_id"]))
    return priority_rows, review_rows


def plan_approved_menu(review: dict, approval: dict) -> dict:
    """Return a local proposal only; caller must recheck DB facts in a future batch."""
    if review.get("review_status") in {"REJECT", "BLOCKED_SOURCE"}:
        raise ValueError("rejected or blocked observation cannot be published")
    if review.get("row_type") != "MENU" or not review.get("menu_name", "").strip():
        raise ValueError("a verified menu name is required")
    if (
        review.get("source_tier") not in {"A", "B"}
        or review.get("store_match_status") != "EXACT_MATCH"
    ):
        raise ValueError("exact A/B evidence is required")
    if review.get("review_status") not in {"AUTO_READY", "QUICK_REVIEW", "DEEP_REVIEW"}:
        raise ValueError("review status is not publishable")
    if approval.get("approved") is not True:
        raise ValueError("explicit human approval is required")
    for field in ("approved_by", "approved_at", "approval_ref"):
        if not approval.get(field):
            raise ValueError(f"missing human {field}")
    for field in (
        "name_verified",
        "source_access_verified",
        "source_current_verified",
        "store_public_verified",
        "fk_verified",
        "duplicate_free",
        "dry_run_passed",
    ):
        if approval.get(field) is not True:
            raise ValueError(f"publish gate failed: {field}")
    price = None
    observed = review.get("observed_price_krw")
    if isinstance(observed, str) and observed.isascii() and observed.isdecimal():
        observed = int(observed)
    if approval.get("price_verified_for_dine_in") is True:
        if (
            review.get("price_context") != "dine_in"
            or type(observed) is not int
            or observed < 0
        ):
            raise ValueError("verified dine-in price evidence is required")
        price = observed
    signature = bool(
        approval.get("signature_verified") is True
        and review.get("source_tier") == "A"
        and review.get("signature_evidence")
    )
    return {
        "menu": {
            "store_id": review["store_id"],
            "name": review["menu_name"].strip(),
            "price": price,
            "is_signature": signature,
        },
        "approval_ref": approval["approval_ref"],
    }


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
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--priority-output", type=Path, required=True)
    parser.add_argument("--review-output", type=Path, required=True)
    args = parser.parse_args()
    if args.priority_output.exists() or args.review_output.exists():
        parser.error("output exists; use versioned paths")
    payload = json.loads(args.input.read_text(encoding="utf-8"))
    priorities, review = build_review_rows(payload)
    write_csv(args.priority_output, PRIORITY_FIELDS, priorities)
    write_csv(args.review_output, REVIEW_FIELDS, review)
    print(f"stores={len(priorities)} review_rows={len(review)}")


if __name__ == "__main__":
    main()
