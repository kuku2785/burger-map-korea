from __future__ import annotations

import csv
import importlib.util
import json
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "apply_kakao_manual_reviews.py"

spec = importlib.util.spec_from_file_location("apply_kakao_manual_reviews", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
reviewer = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = reviewer
spec.loader.exec_module(reviewer)


class KakaoManualReviewTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.input_path = self.temp_path / "input.csv"
        self.output_path = self.temp_path / "output.csv"
        self.decisions_path = self.temp_path / "decisions.json"
        self.fieldnames = [
            "discoveryId",
            "sourcePlaceId",
            "name",
            "matchStatus",
            "screeningStatus",
        ]
        self.input_rows = [
            {
                "discoveryId": "kakao_S1",
                "sourcePlaceId": "S1",
                "name": "가상버거 하나",
                "matchStatus": "existing_match",
                "screeningStatus": "pending",
            },
            {
                "discoveryId": "kakao_S2",
                "sourcePlaceId": "S2",
                "name": "가상버거 둘",
                "matchStatus": "possible_duplicate",
                "screeningStatus": "needs_recheck",
            },
            {
                "discoveryId": "kakao_S3",
                "sourcePlaceId": "S3",
                "name": "가상식당 셋",
                "matchStatus": "new_candidate",
                "screeningStatus": "needs_recheck",
            },
        ]
        with self.input_path.open("w", encoding="utf-8-sig", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=self.fieldnames)
            writer.writeheader()
            writer.writerows(self.input_rows)
        self.write_decisions()

    def write_decisions(self, *, second_expected_name: str = "가상버거 둘") -> None:
        decisions = {
            "version": 1,
            "expectedInputRows": 3,
            "decisions": [
                {
                    "sourcePlaceId": "S1",
                    "expectedName": "가상버거 하나",
                    "manualReviewStatus": "pending",
                    "manualReviewAction": "link_existing",
                    "manualReviewNote": "가상 기존 연결",
                },
                {
                    "sourcePlaceId": "S2",
                    "expectedName": second_expected_name,
                    "manualReviewStatus": "pending",
                    "manualReviewAction": "add_pending",
                    "manualReviewNote": "가상 false duplicate",
                    "possibleDuplicateDecision": "false_duplicate",
                },
                {
                    "sourcePlaceId": "S3",
                    "expectedName": "가상식당 셋",
                    "manualReviewStatus": "rejected",
                    "manualReviewAction": "reject",
                    "manualReviewNote": "가상 제외",
                },
            ],
        }
        self.decisions_path.write_text(
            json.dumps(decisions, ensure_ascii=False), encoding="utf-8"
        )

    def test_preserves_original_fields_values_and_row_order(self) -> None:
        rows, status_counts, action_counts = reviewer.apply_manual_reviews(
            self.input_path, self.output_path, self.decisions_path
        )
        with self.output_path.open("r", encoding="utf-8-sig", newline="") as file:
            reader = csv.DictReader(file)
            output_headers = reader.fieldnames
            output_rows = list(reader)

        self.assertEqual(output_headers, self.fieldnames + list(reviewer.MANUAL_REVIEW_HEADERS))
        self.assertEqual(
            [row["sourcePlaceId"] for row in output_rows],
            [row["sourcePlaceId"] for row in self.input_rows],
        )
        for original, output in zip(self.input_rows, output_rows):
            self.assertEqual(
                {field: output[field] for field in self.fieldnames}, original
            )
        self.assertEqual(len(rows), 3)
        self.assertEqual(status_counts, Counter({"pending": 2, "rejected": 1}))
        self.assertEqual(
            action_counts,
            Counter({"link_existing": 1, "add_pending": 1, "reject": 1}),
        )
        self.assertNotIn("verified", status_counts)

    def test_expected_name_mismatch_stops_before_writing(self) -> None:
        self.write_decisions(second_expected_name="다른 가상 이름")

        with self.assertRaises(reviewer.ManualReviewError):
            reviewer.apply_manual_reviews(
                self.input_path, self.output_path, self.decisions_path
            )

        self.assertFalse(self.output_path.exists())

    def test_existing_output_is_not_overwritten(self) -> None:
        self.output_path.write_text("keep", encoding="utf-8")

        with self.assertRaises(reviewer.ManualReviewError):
            reviewer.apply_manual_reviews(
                self.input_path, self.output_path, self.decisions_path
            )

        self.assertEqual(self.output_path.read_text(encoding="utf-8"), "keep")

if __name__ == "__main__":
    unittest.main()
