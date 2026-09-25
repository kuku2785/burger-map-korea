from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "data" / "build_menu_evidence_review.py"
spec = importlib.util.spec_from_file_location("build_menu_evidence_review", SCRIPT)
assert spec and spec.loader
pipeline = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pipeline
spec.loader.exec_module(pipeline)


def sample_source(**changes):
    source = {
        "url": "https://shop.example/menu",
        "source_type": "official_store_page",
        "ownership_verified": True,
        "source_store_name": "버거집 본점",
        "source_address": "서울 용산구 한강대로 1",
        "checked_at": "2026-09-24T00:00:00Z",
        "current_menu": True,
        "menus": [
            {
                "name_raw": "Double Cheese Burger",
                "price_raw": "10,800원",
                "price_context": "dine_in",
            }
        ],
    }
    source.update(changes)
    return source


def sample_payload(*sources):
    return {
        "stores": [
            {
                "id": "11111111-1111-4111-8111-111111111111",
                "name": "버거집 본점",
                "address": "서울 용산구 한강대로 1",
                "sources": list(sources),
            }
        ]
    }


class MenuEvidenceReviewTest(unittest.TestCase):
    def test_exact_price_only_and_conservative_name_normalization(self):
        self.assertEqual(pipeline.parse_price("10,800원"), 10800)
        for raw in ("10.8", "1.08", "10,800원~", "시가", "10,800", ""):
            self.assertIsNone(pipeline.parse_price(raw), raw)
        self.assertEqual(
            pipeline.normalize_name(" DOUBLE,  CHEESE Burger! "), "double cheese burger"
        )
        self.assertNotEqual(pipeline.normalize_name("더블 치즈 버거"), "double cheese burger")

    def test_prior_csv_numeric_price_is_explicitly_distinct_from_raw_text(self):
        self.assertIsNone(pipeline.parse_price("10800"))
        self.assertEqual(
            pipeline.observed_price_krw(
                {"price_raw": "10800", "price_record_kind": "prior_csv_numeric_krw"}
            ),
            10800,
        )
        source = sample_source(
            menus=[
                {
                    "name_raw": "Burger",
                    "price_raw": "10800",
                    "price_record_kind": "prior_csv_numeric_krw",
                    "price_context": "dine_in",
                }
            ]
        )
        _, rows = pipeline.build_review(sample_payload(source))
        self.assertEqual(rows[0]["decision_suggestion"], "READY_WITHOUT_PRICE")
        self.assertIsNone(rows[0]["publish_price_krw"])

    def test_current_official_exact_dine_in_can_be_ready_with_price(self):
        discovery, rows = pipeline.build_review(sample_payload(sample_source()))
        self.assertEqual(len(discovery), 1)
        self.assertEqual(rows[0]["source_store_match"], "EXACT_MATCH")
        self.assertEqual(rows[0]["decision_suggestion"], "READY_WITH_PRICE")
        self.assertEqual(rows[0]["publish_price_krw"], 10800)
        self.assertFalse(rows[0]["human_approved"])

    def test_delivery_price_is_retained_but_not_public_price(self):
        source = sample_source(
            source_type="delivery_platform",
            ownership_verified=False,
            menus=[
                {"name_raw": "버거", "price_raw": "10,800원", "price_context": "delivery"}
            ],
        )
        _, rows = pipeline.build_review(sample_payload(source))
        self.assertEqual(rows[0]["observed_price_krw"], 10800)
        self.assertIsNone(rows[0]["publish_price_krw"])
        self.assertEqual(rows[0]["decision_suggestion"], "NEEDS_REVIEW")

    def test_official_order_channel_price_does_not_become_public_price(self):
        source = sample_source(
            source_type="official_order",
            menus=[
                {
                    "name_raw": "버거",
                    "price_raw": "10,800원",
                    "price_context": "order_channel",
                    "signature_claim": True,
                }
            ],
        )
        _, rows = pipeline.build_review(sample_payload(source))
        self.assertEqual(rows[0]["decision_suggestion"], "READY_WITHOUT_PRICE")
        self.assertEqual(rows[0]["observed_price_krw"], 10800)
        self.assertIsNone(rows[0]["publish_price_krw"])
        self.assertTrue(rows[0]["is_signature_candidate"])
        self.assertFalse(rows[0]["human_approved"])

    def test_blocked_and_identity_mismatch_cannot_be_ready(self):
        blocked = sample_source(access_status="BLOCKED_SOURCE")
        mismatch = sample_source(source_address="서울 용산구 한강대로 9")
        _, rows = pipeline.build_review(sample_payload(blocked, mismatch))
        self.assertEqual(
            [row["decision_suggestion"] for row in rows], ["BLOCKED_SOURCE", "REJECT"]
        )
        self.assertEqual(rows[1]["source_store_match"], "MISMATCH")

    def test_mismatch_rejected_and_duplicate_flagged(self):
        source = sample_source(source_address="서울 용산구 한강대로 9")
        _, rows = pipeline.build_review(sample_payload(source))
        self.assertEqual(rows[0]["decision_suggestion"], "REJECT")
        _, rows = pipeline.build_review(
            sample_payload(
                sample_source(), sample_source(url="https://other.example/menu")
            )
        )
        self.assertEqual(rows[1]["decision_suggestion"], "NEEDS_REVIEW")
        self.assertEqual(rows[1]["duplicate_of"], "https://shop.example/menu")

    def test_official_claim_needs_owner_and_current_menu(self):
        unknown = sample_source(ownership_verified=False)
        historic = sample_source(current_menu=False)
        _, unknown_rows = pipeline.build_review(sample_payload(unknown))
        _, historic_rows = pipeline.build_review(sample_payload(historic))
        self.assertEqual(unknown_rows[0]["source_tier"], "C")
        self.assertEqual(unknown_rows[0]["decision_suggestion"], "NEEDS_REVIEW")
        self.assertEqual(historic_rows[0]["decision_suggestion"], "NEEDS_REVIEW")

    def test_pilot_is_offline_and_no_row_is_approved(self):
        payload = json.loads(
            (ROOT / "docs" / "menu-pipeline-pilot-input-2026-09-24.json").read_text(
                encoding="utf-8"
            )
        )
        discovery, rows = pipeline.build_review(payload)
        self.assertEqual((len(payload["stores"]), len(discovery), len(rows)), (5, 5, 8))
        self.assertTrue(all(not row["human_approved"] for row in rows))
        self.assertTrue(all(row["publish_price_krw"] is None for row in rows))
        self.assertEqual(
            sum(row["decision_suggestion"] == "BLOCKED_SOURCE" for row in rows), 4
        )
        self.assertEqual(sum(row["decision_suggestion"] == "REJECT" for row in rows), 1)

    def test_output_does_not_overwrite_existing_review(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "review.csv"
            target.write_text("user work", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                pipeline.write_csv(target, pipeline.FIELDS, [])
            self.assertEqual(target.read_text(encoding="utf-8"), "user work")

    def test_secret_bearing_url_is_rejected_before_artifact_write(self):
        source = sample_source(url="https://shop.example/menu?access_token=example")
        with self.assertRaisesRegex(ValueError, "without credentials"):
            pipeline.build_review(sample_payload(source))


if __name__ == "__main__":
    unittest.main()
