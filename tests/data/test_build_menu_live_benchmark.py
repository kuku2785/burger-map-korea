from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "data" / "build_menu_live_benchmark.py"
spec = importlib.util.spec_from_file_location("build_menu_live_benchmark", SCRIPT)
assert spec and spec.loader
benchmark = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = benchmark
spec.loader.exec_module(benchmark)


def store(*sources, searches=None):
    return {
        "store_id": "11111111-1111-4111-8111-111111111111",
        "store_name": "Example Burger",
        "address": "서울 용산구 테스트로 1",
        "district": "용산구",
        "searches": searches if searches is not None else ["Example Burger 메뉴"],
        "sources": list(sources),
    }


def source(**changes):
    row = {
        "source_url": "https://example.org/menu",
        "source_type": "official_store_page",
        "source_tier": "A",
        "store_match": "EXACT_MATCH",
        "access_status": "ACCESSIBLE",
        "currentness": "HIGH",
        "candidates": [
            {
                "menu_name": "Classic Burger",
                "displayed_price": "10,800원",
                "price_krw": 10800,
                "price_context": "dine_in",
                "signature_wording": "대표 메뉴",
                "extraction_method": "opened_html_text",
            }
        ],
    }
    row.update(changes)
    return row


class LiveBenchmarkTest(unittest.TestCase):
    def test_adaptive_search_stops_on_credible_exact_current_menu(self):
        calls = []

        def search(query):
            calls.append(query)
            return [query]

        def inspect(hit):
            if len(calls) == 1:
                return {
                    "source_tier": "C",
                    "store_match": "EXACT_MATCH",
                    "access_status": "ACCESSIBLE",
                    "currentness": "HIGH",
                    "menu_extracted": True,
                }
            return {
                "source_tier": "A",
                "store_match": "EXACT_MATCH",
                "access_status": "ACCESSIBLE",
                "currentness": "HIGH",
                "menu_extracted": True,
            }

        executed, results = benchmark.adaptive_search(store(), search, inspect)
        self.assertEqual(len(executed), 2)
        self.assertEqual(len(results), 2)
        self.assertEqual(executed, calls)

    def test_accessible_official_menu_counts_but_publish_is_not_approved(self):
        stores, sources, candidates, metrics = benchmark.build_rows(
            {"stores": [store(source())]}
        )
        self.assertEqual(metrics["stores_with_menu_extraction"], 1)
        self.assertEqual(metrics["stores_with_price_extraction"], 1)
        self.assertEqual(metrics["stores_with_signature_extraction"], 1)
        self.assertEqual(stores[0]["automation_class"], "FULLY_AUTOMATABLE")
        self.assertEqual(candidates[0]["suggested_decision"], "NEEDS_REVIEW")
        self.assertEqual(sources[0]["http_status"], "")

    def test_blocked_source_is_not_no_source_or_no_menu(self):
        blocked = source(
            access_status="BLOCKED_SOURCE", candidates=[], currentness="UNKNOWN"
        )
        stores, sources, candidates, metrics = benchmark.build_rows(
            {"stores": [store(blocked)]}
        )
        self.assertEqual(stores[0]["automation_class"], "SOURCE_BLOCKED")
        self.assertEqual(metrics["stores_with_any_source"], 1)
        self.assertEqual(metrics["no_source_stores"], 0)
        self.assertEqual(metrics["stores_with_menu_extraction"], 0)
        self.assertEqual(candidates, [])
        self.assertEqual(sources[0]["access_status"], "BLOCKED_SOURCE")

    def test_source_without_menu_is_retained_and_unknown_price_not_counted(self):
        no_price = source(
            candidates=[
                {"menu_name": "Burger", "price_krw": None, "price_context": "unknown"}
            ]
        )
        _, source_rows, candidate_rows, metrics = benchmark.build_rows(
            {"stores": [store(no_price)]}
        )
        self.assertEqual(len(source_rows), 1)
        self.assertEqual(len(candidate_rows), 1)
        self.assertEqual(metrics["stores_with_menu_extraction"], 1)
        self.assertEqual(metrics["stores_with_price_extraction"], 0)

    def test_unverified_identity_cannot_emit_menu_candidate(self):
        for match in ("AMBIGUOUS", "MISMATCH", "UNKNOWN"):
            with self.subTest(match=match):
                with self.assertRaisesRegex(ValueError, "unverified store identity"):
                    benchmark.build_rows({"stores": [store(source(store_match=match))]})

    def test_inaccessible_page_cannot_emit_menu_candidate(self):
        with self.assertRaisesRegex(ValueError, "inaccessible source"):
            benchmark.build_rows(
                {"stores": [store(source(access_status="FETCH_ERROR"))]}
            )

    def test_inaccessible_source_cannot_claim_retrieval_dates(self):
        blocked = source(
            access_status="FETCH_ERROR", candidates=[], retrieved_at="2026-09-24"
        )
        with self.assertRaisesRegex(ValueError, "cannot have observed/retrieved dates"):
            benchmark.build_rows({"stores": [store(blocked)]})

    def test_secret_url_rejected_and_existing_artifact_preserved(self):
        with self.assertRaisesRegex(ValueError, "without credentials"):
            benchmark.build_rows(
                {
                    "stores": [
                        store(source(source_url="https://example.org/menu?token=x"))
                    ]
                }
            )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "stores.csv"
            path.write_text("user work", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                benchmark.write_csv(path, benchmark.STORE_FIELDS, [])
            self.assertEqual(path.read_text(encoding="utf-8"), "user work")

    def test_search_metrics_and_empty_store_are_distinct(self):
        first = store(source(), searches=["one", "two"])
        second = store(searches=["three"])
        second["store_id"] = "22222222-2222-4222-8222-222222222222"
        stores, _, _, metrics = benchmark.build_rows({"stores": [first, second]})
        self.assertEqual(metrics["searches_executed"], 3)
        self.assertEqual(metrics["searches_per_store_mean"], 1.5)
        self.assertEqual(metrics["searches_per_store_median"], 1.5)
        self.assertEqual(metrics["no_source_stores"], 1)
        self.assertEqual(stores[1]["automation_class"], "INSUFFICIENT_EVIDENCE")

    def test_actual_searches_over_cap_are_counted_and_flagged(self):
        row = store(searches=[f"query-{i}" for i in range(8)])
        row["additional_searches_after_cap"] = ["query-8", "query-9"]
        stores, _, _, metrics = benchmark.build_rows({"stores": [row]})
        self.assertEqual(stores[0]["searches_executed"], 10)
        self.assertTrue(stores[0]["search_cap_exceeded"])
        self.assertEqual(metrics["stores_exceeding_search_cap"], 1)

    def test_c_tier_cannot_suggest_ready(self):
        untrusted = source(source_tier="C")
        untrusted["candidates"][0]["suggested_decision"] = "READY_WITH_PRICE"
        with self.assertRaisesRegex(ValueError, "Tier C"):
            benchmark.build_rows({"stores": [store(untrusted)]})


if __name__ == "__main__":
    unittest.main()
