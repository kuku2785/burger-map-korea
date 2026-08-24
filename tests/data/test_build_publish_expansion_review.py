from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = (
    PROJECT_ROOT / "scripts" / "data" / "build_publish_expansion_review.py"
)
FIXTURE_PATH = (
    PROJECT_ROOT / "tests" / "fixtures" / "virtual_publish_expansion_evidence.json"
)

spec = importlib.util.spec_from_file_location(
    "build_publish_expansion_review", SCRIPT_PATH
)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Unable to load script: {SCRIPT_PATH}")
review_builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = review_builder
spec.loader.exec_module(review_builder)


class PublishExpansionReviewTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.staging_path = self.root / "staging.csv"
        self.publish_path = self.root / "publish.csv"
        self.style_path = self.root / "style.csv"
        self.hold_path = self.root / "hold.csv"
        self.evidence_path = self.root / "evidence.json"
        self.output_path = self.root / "expansion.csv"
        self.staging_headers = [
            "candidateId",
            "displayName",
            "address",
            "latitude",
            "longitude",
        ]
        self.publish_headers = [
            "storeId",
            "candidateId",
            "name",
            "address",
            "latitude",
            "longitude",
            "publishDecision",
            "isActive",
        ]
        self.style_headers = [
            "storeId",
            "candidateId",
            "name",
            "address",
            "proposedBurgerStyle",
            "reviewStatus",
        ]
        self.hold_headers = ["candidateId", "name", "stagingStatus"]
        self.staging_rows: list[dict[str, str]] = []
        self.publish_rows: list[dict[str, str]] = []
        self.style_rows: list[dict[str, str]] = []
        for index in range(1, 5):
            suffix = f"{index:03d}"
            candidate_id = (
                f"virtual_pending_{suffix}" if index <= 3 else "virtual_public_004"
            )
            name = f"Virtual Burger {index}"
            address = f"1{index} Test Road"
            latitude = f"{37.50 + index / 1000:.3f}"
            longitude = f"{126.90 + index / 1000:.3f}"
            store_id = str(uuid.UUID(f"00000000-0000-4000-8000-{index:012d}"))
            self.staging_rows.append(
                {
                    "candidateId": candidate_id,
                    "displayName": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                }
            )
            self.publish_rows.append(
                {
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                    "publishDecision": "pending" if index <= 3 else "verified",
                    "isActive": "false" if index <= 3 else "true",
                }
            )
            self.style_rows.append(
                {
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "proposedBurgerStyle": "classic"
                    if index != 3
                    else "unclassified",
                    "reviewStatus": "approved"
                    if index != 3
                    else "needs_recheck",
                }
            )
        self.hold_rows = [
            {
                "candidateId": "virtual_hold_001",
                "name": "Virtual Hold Store",
                "stagingStatus": "hold_needs_recheck",
            }
        ]
        self.evidence_path.write_text(
            FIXTURE_PATH.read_text(encoding="utf-8"), encoding="utf-8"
        )
        self.write_inputs()

    @staticmethod
    def write_csv(
        path: Path, headers: list[str], rows: list[dict[str, str]]
    ) -> None:
        with path.open("w", encoding="utf-8-sig", newline="") as output_file:
            writer = csv.DictWriter(output_file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)

    @staticmethod
    def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            reader = csv.DictReader(input_file)
            return list(reader.fieldnames or []), list(reader)

    @staticmethod
    def sha256(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def write_inputs(self) -> None:
        self.write_csv(self.staging_path, self.staging_headers, self.staging_rows)
        self.write_csv(self.publish_path, self.publish_headers, self.publish_rows)
        self.write_csv(self.style_path, self.style_headers, self.style_rows)
        self.write_csv(self.hold_path, self.hold_headers, self.hold_rows)

    def generate(self):
        return review_builder.build_publish_expansion_review(
            self.staging_path,
            self.publish_path,
            self.style_path,
            self.hold_path,
            self.evidence_path,
            self.output_path,
            expected_pending_rows=3,
        )

    def test_builds_pending_review_in_order_without_approval(self) -> None:
        input_paths = (
            self.staging_path,
            self.publish_path,
            self.style_path,
            self.hold_path,
        )
        hashes_before = {path: self.sha256(path) for path in input_paths}

        rows = self.generate()

        self.assertEqual(len(rows), 3)
        self.assertEqual([row["reviewNumber"] for row in rows], ["1", "2", "3"])
        self.assertEqual(
            [row["candidateId"] for row in rows],
            [f"virtual_pending_{index:03d}" for index in range(1, 4)],
        )
        self.assertTrue(all(row["currentPublishDecision"] == "pending" for row in rows))
        self.assertTrue(all(row["currentIsActive"] == "false" for row in rows))
        self.assertNotIn("virtual_public_004", {row["candidateId"] for row in rows})
        self.assertNotIn("virtual_hold_001", {row["candidateId"] for row in rows})
        self.assertEqual(
            [row["recommendedDecision"] for row in rows],
            [
                "ready_for_user_approval",
                "ready_for_user_approval",
                "needs_manual_check",
            ],
        )
        self.assertEqual(rows[0]["officialSourceAvailable"], "true")
        self.assertEqual(rows[1]["recentEvidenceCount"], "2")
        self.assertEqual(rows[2]["currentBurgerStyle"], "unclassified")
        self.assertEqual(self.read_csv(self.output_path)[0], list(review_builder.OUTPUT_HEADERS))
        self.assertEqual(
            hashes_before, {path: self.sha256(path) for path in input_paths}
        )

    def test_is_deterministic_and_preserves_reviewer_note(self) -> None:
        self.generate()
        headers, rows = self.read_csv(self.output_path)
        rows[0]["reviewerNote"] = "Human decision stays local."
        self.write_csv(self.output_path, headers, rows)

        first = self.generate()
        first_hash = self.sha256(self.output_path)
        second = self.generate()

        self.assertEqual(first[0]["reviewerNote"], "Human decision stays local.")
        self.assertEqual(second, first)
        self.assertEqual(self.sha256(self.output_path), first_hash)

    def test_blocks_input_identity_coordinate_and_id_errors(self) -> None:
        mutations = (
            lambda: self.publish_rows[0].update(address="Changed Road"),
            lambda: self.publish_rows[0].update(latitude="91"),
            lambda: self.publish_rows[1].update(
                storeId=self.publish_rows[0]["storeId"]
            ),
            lambda: self.staging_rows[0].update(
                candidateId=self.hold_rows[0]["candidateId"]
            ),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.setUp()
                mutation()
                self.write_inputs()
                with self.assertRaises(review_builder.StorePublishingError):
                    self.generate()

    def test_blocks_missing_extra_or_duplicate_evidence(self) -> None:
        payload = json.loads(self.evidence_path.read_text(encoding="utf-8"))
        cases = (
            payload["stores"][:-1],
            payload["stores"] + [dict(payload["stores"][0])],
        )
        for stores in cases:
            with self.subTest(store_count=len(stores)):
                self.evidence_path.write_text(
                    json.dumps(
                        {"checkedAt": "2026-08-24", "stores": stores}, indent=2
                    ),
                    encoding="utf-8",
                )
                with self.assertRaises(review_builder.StorePublishingError):
                    self.generate()
                self.evidence_path.write_text(
                    FIXTURE_PATH.read_text(encoding="utf-8"), encoding="utf-8"
                )

    def test_blocks_ready_recommendation_without_gate(self) -> None:
        payload = json.loads(self.evidence_path.read_text(encoding="utf-8"))
        payload["stores"][2]["recommendedDecision"] = "ready_for_user_approval"
        self.evidence_path.write_text(json.dumps(payload), encoding="utf-8")

        with self.assertRaises(review_builder.StorePublishingError):
            self.generate()

    def test_blocks_secret_url_future_date_and_unchecked_source(self) -> None:
        mutations = (
            lambda source: source.update(
                url="https://example.com/" + "AIza" + ("0" * 34)
            ),
            lambda source: source.update(publishedAt="2026-09-01"),
            lambda source: source.update(checkedDirectly=False),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                payload = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
                mutation(payload["stores"][0]["sources"][0])
                self.evidence_path.write_text(json.dumps(payload), encoding="utf-8")
                with self.assertRaises(review_builder.StorePublishingError):
                    self.generate()

    def test_likely_closed_remains_a_user_decision(self) -> None:
        payload = json.loads(self.evidence_path.read_text(encoding="utf-8"))
        store = payload["stores"][2]
        store["operatingStatusAssessment"] = "possible_closed"
        store["recommendedDecision"] = "likely_closed_needs_user_decision"
        self.evidence_path.write_text(json.dumps(payload), encoding="utf-8")

        rows = self.generate()

        self.assertEqual(
            rows[2]["recommendedDecision"],
            "likely_closed_needs_user_decision",
        )
        self.assertEqual(rows[2]["currentPublishDecision"], "pending")
        self.assertEqual(rows[2]["currentIsActive"], "false")


if __name__ == "__main__":
    unittest.main()
