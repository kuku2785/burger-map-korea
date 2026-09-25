from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "data" / "build_menu_pipeline_v1.py"
spec = importlib.util.spec_from_file_location("build_menu_pipeline_v1", SCRIPT)
assert spec and spec.loader
pipeline = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pipeline
spec.loader.exec_module(pipeline)


def source(**changes):
    result = {
        "source_url": "https://example.org/menu",
        "source_type": "official_store_page",
        "source_tier": "A",
        "store_match": "EXACT_MATCH",
        "access_status": "ACCESSIBLE",
        "currentness": "HIGH",
        "retrieved_at": "2026-09-24T00:00:00Z",
        "candidates": [
            {
                "menu_name": "Classic Burger",
                "price_krw": 10800,
                "price_context": "order_channel",
                "signature_wording": "signature",
            }
        ],
    }
    result.update(changes)
    return result


def store(*sources):
    return {
        "store_id": "11111111-1111-4111-8111-111111111111",
        "store_name": "Example Burger",
        "address": "Test Road 1",
        "district": "Yongsan",
        "sources": list(sources),
    }


def review_row(**changes):
    result = {
        "store_id": store()["store_id"],
        "row_type": "MENU",
        "menu_name": "Classic Burger",
        "observed_price_krw": "10800",
        "price_context": "order_channel",
        "source_tier": "A",
        "store_match_status": "EXACT_MATCH",
        "review_status": "AUTO_READY",
        "signature_evidence": "signature",
    }
    result.update(changes)
    return result


def approval(**changes):
    result = {
        "approved": True,
        "approved_by": "reviewer",
        "approved_at": "2026-09-24",
        "approval_ref": "review-1",
        "name_verified": True,
        "source_access_verified": True,
        "source_current_verified": True,
        "store_public_verified": True,
        "fk_verified": True,
        "duplicate_free": True,
        "dry_run_passed": True,
    }
    result.update(changes)
    return result


class MenuPipelineV1Test(unittest.TestCase):
    def test_search_stops_early_only_for_accessible_exact_ab_menu(self):
        seen = []

        def search(query):
            seen.append(query)
            return [query]

        def inspect(_):
            if len(seen) == 1:
                return source(source_tier="C")
            return source(source_tier="B")

        queries, observations = pipeline.adaptive_discover(store(), search, inspect)
        self.assertEqual(len(queries), 2)
        self.assertEqual(len(observations), 2)

    def test_search_continues_to_cap_without_menu_and_rejects_excess_budget(self):
        calls = []

        def search(query):
            calls.append(query)
            return [query]

        queries, _ = pipeline.adaptive_discover(
            store(), search, lambda _: source(candidates=[])
        )
        self.assertEqual(len(queries), 5)
        self.assertEqual(queries, calls)
        with self.assertRaises(ValueError):
            pipeline.adaptive_discover(store(), search, lambda _: source(), maximum=6)

        no_leads, _ = pipeline.adaptive_discover(
            store(), lambda _: [], lambda _: source()
        )
        self.assertEqual(len(no_leads), 3)

    def test_review_classification_distinguishes_trust_identity_access_and_age(self):
        candidate = source()["candidates"][0]
        cases = [
            (source(), "AUTO_READY"),
            (source(currentness="UNKNOWN"), "QUICK_REVIEW"),
            (source(source_tier="B"), "QUICK_REVIEW"),
            (source(source_tier="C"), "DEEP_REVIEW"),
            (source(store_match="AMBIGUOUS"), "DEEP_REVIEW"),
            (source(store_match="MISMATCH"), "REJECT"),
            (source(access_status="FETCH_ERROR"), "DEEP_REVIEW"),
            (source(access_status="BLOCKED_SOURCE"), "BLOCKED_SOURCE"),
        ]
        for observation, expected in cases:
            with self.subTest(expected=expected, observation=observation):
                self.assertEqual(
                    pipeline.classify_review(observation, candidate)[0], expected
                )
        self.assertEqual(
            pipeline.classify_review(source(candidates=[]), None)[0], "DEEP_REVIEW"
        )

    def test_priority_and_review_queue_never_imply_approval_or_price(self):
        high = store(source())
        medium = store(source(source_tier="C"))
        medium["store_id"] = "22222222-2222-4222-8222-222222222222"
        low = store(source(store_match="MISMATCH"))
        low["store_id"] = "33333333-3333-4333-8333-333333333333"
        priorities, reviews = pipeline.build_review_rows(
            {"stores": [low, medium, high]}
        )
        self.assertEqual([r["priority"] for r in priorities], ["HIGH", "MEDIUM", "LOW"])
        self.assertEqual(
            [r["selection_status"] for r in priorities],
            ["PILOT_CANDIDATE", "LATER_REVIEW", "LATER_REVIEW"],
        )
        self.assertTrue(all(r["human_approved"] is False for r in reviews))
        self.assertTrue(all(r["suggested_public_price_krw"] == "" for r in reviews))
        self.assertEqual(reviews[0]["access_status"], "ACCESSIBLE")
        self.assertEqual(
            pipeline.normalize_menu_name(" ＢＵＲＧＥＲ  Deluxe! "), "burger deluxe"
        )
        with self.assertRaisesRegex(ValueError, "duplicate store ID"):
            pipeline.build_review_rows({"stores": [high, high]})
        with self.assertRaisesRegex(ValueError, "without credentials"):
            pipeline.build_review_rows(
                {
                    "stores": [
                        store(source(source_url="https://example.org/?token=private"))
                    ]
                }
            )

    def test_publish_gate_requires_human_approval_and_independent_checks(self):
        for invalid in (
            approval(approved=False),
            approval(approved_by=""),
            approval(name_verified=False),
            approval(source_access_verified=False),
            approval(source_current_verified=False),
            approval(store_public_verified=False),
            approval(fk_verified=False),
            approval(duplicate_free=False),
            approval(dry_run_passed=False),
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    pipeline.plan_approved_menu(review_row(), invalid)
        for invalid in (
            review_row(source_tier="C"),
            review_row(store_match_status="LIKELY_MATCH"),
            review_row(review_status="REJECT"),
            review_row(review_status="BLOCKED_SOURCE"),
            review_row(row_type="SOURCE"),
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    pipeline.plan_approved_menu(invalid, approval())

    def test_price_and_signature_are_conservative(self):
        proposal = pipeline.plan_approved_menu(
            review_row(), approval(signature_verified=True)
        )
        self.assertIsNone(proposal["menu"]["price"])
        self.assertTrue(proposal["menu"]["is_signature"])
        self.assertEqual(
            set(proposal["menu"]), {"store_id", "name", "price", "is_signature"}
        )
        with self.assertRaisesRegex(ValueError, "dine-in"):
            pipeline.plan_approved_menu(
                review_row(), approval(price_verified_for_dine_in=True)
            )
        dine_in = review_row(price_context="dine_in")
        self.assertIsNone(
            pipeline.plan_approved_menu(dine_in, approval())["menu"]["price"]
        )
        verified = pipeline.plan_approved_menu(
            dine_in, approval(price_verified_for_dine_in=True)
        )
        self.assertEqual(verified["menu"]["price"], 10800)
        c_tier = review_row(source_tier="B", signature_evidence="signature")
        self.assertFalse(
            pipeline.plan_approved_menu(c_tier, approval(signature_verified=True))[
                "menu"
            ]["is_signature"]
        )
        for bad_price in ("10,800", "10.8", -1, True):
            with self.subTest(bad_price=bad_price):
                with self.assertRaises(ValueError):
                    pipeline.plan_approved_menu(
                        review_row(
                            price_context="dine_in", observed_price_krw=bad_price
                        ),
                        approval(price_verified_for_dine_in=True),
                    )

    def test_recorded_benchmark_and_output_preservation(self):
        payload = json.loads(
            (ROOT / "docs" / "menu-live-benchmark-input-2026-09-24.json").read_text(
                encoding="utf-8"
            )
        )
        priorities, reviews = pipeline.build_review_rows(payload)
        self.assertEqual(len(priorities), 24)
        self.assertEqual(sum(r["source_count"] for r in priorities), 30)
        self.assertTrue(all(not r["human_approved"] for r in reviews))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "review.csv"
            pipeline.write_csv(path, pipeline.REVIEW_FIELDS, reviews)
            before = path.read_bytes()
            with self.assertRaises(FileExistsError):
                pipeline.write_csv(path, pipeline.REVIEW_FIELDS, reviews)
            self.assertEqual(path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
