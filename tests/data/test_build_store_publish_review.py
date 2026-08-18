from __future__ import annotations

import csv
import hashlib
import importlib.util
import shutil
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "build_store_publish_review.py"
STAGING_FIXTURE = PROJECT_ROOT / "tests" / "fixtures" / "virtual_yongsan_staging.csv"
MIGRATION_PATH = (
    PROJECT_ROOT / "supabase" / "migrations" / "0001_init_store_schema.sql"
)

spec = importlib.util.spec_from_file_location("build_store_publish_review", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
review_builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = review_builder
spec.loader.exec_module(review_builder)


class StorePublishReviewBuilderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.staging_path = self.temp_path / "staging.csv"
        self.hold_path = self.temp_path / "hold.csv"
        self.output_path = self.temp_path / "publish_review.csv"
        shutil.copyfile(STAGING_FIXTURE, self.staging_path)
        self.write_csv(
            self.hold_path,
            ["candidateId", "sourcePlaceId", "name", "previousStatus", "stagingStatus", "holdReason", "recommendedAction"],
            [
                {
                    "candidateId": f"hold-{index}",
                    "sourcePlaceId": "",
                    "name": f"가상 보류 매장 {index}",
                    "previousStatus": "needs_recheck",
                    "stagingStatus": "hold_needs_recheck",
                    "holdReason": "합성 보류 사유",
                    "recommendedAction": "수동 확인",
                }
                for index in range(1, 5)
            ],
        )
        self.uuid_values = iter(
            uuid.UUID(f"00000000-0000-4000-8000-{index:012d}")
            for index in range(1, 25)
        )

    @staticmethod
    def write_csv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
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

    def generate(self):
        return review_builder.generate_publish_review(
            self.staging_path,
            self.hold_path,
            MIGRATION_PATH,
            self.output_path,
            uuid_factory=lambda: next(self.uuid_values),
        )

    def test_generates_24_pending_inactive_rows_without_modifying_inputs(self) -> None:
        staging_hash = self.sha256(self.staging_path)
        hold_hash = self.sha256(self.hold_path)

        rows = self.generate()

        self.assertEqual(len(rows), 24)
        self.assertEqual(len({row["storeId"] for row in rows}), 24)
        self.assertTrue(all(row["publishDecision"] == "pending" for row in rows))
        self.assertTrue(all(row["isActive"] == "false" for row in rows))
        self.assertEqual(
            {source_type: sum(row["sourceType"] == source_type for row in rows) for source_type in {"mixed", "manual_review"}},
            {"mixed": 14, "manual_review": 10},
        )
        self.assertTrue(all(row["sourceAsOf"] == "" for row in rows))
        self.assertEqual(self.sha256(self.staging_path), staging_hash)
        self.assertEqual(self.sha256(self.hold_path), hold_hash)

    def test_preserves_store_ids_and_manual_fields_on_refresh(self) -> None:
        first_rows = self.generate()
        headers, saved_rows = self.read_csv(self.output_path)
        saved_rows[0].update(
            {
                "burgerStyle": "스매시",
                "sourceAsOf": "2026-08-18",
                "publishDecision": "needs_recheck",
                "verificationNote": "합성 추가 확인",
            }
        )
        self.write_csv(self.output_path, headers, saved_rows)

        second_rows = review_builder.generate_publish_review(
            self.staging_path,
            self.hold_path,
            MIGRATION_PATH,
            self.output_path,
            uuid_factory=lambda: self.fail("기존 행에 새 UUID를 만들면 안 됩니다."),
        )

        self.assertEqual(
            [row["storeId"] for row in second_rows],
            [row["storeId"] for row in first_rows],
        )
        self.assertEqual(second_rows[0]["burgerStyle"], "스매시")
        self.assertEqual(second_rows[0]["publishDecision"], "needs_recheck")

    def test_blocks_a_hold_store_from_the_review_table(self) -> None:
        headers, staging_rows = self.read_csv(self.staging_path)
        staging_rows[0]["candidateId"] = "hold-1"
        staging_rows[0]["displayName"] = "가상 보류 매장 1"
        self.write_csv(self.staging_path, headers, staging_rows)

        with self.assertRaises(review_builder.StorePublishingError):
            self.generate()


if __name__ == "__main__":
    unittest.main()
