from __future__ import annotations

import csv
import importlib.util
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
TEST_DIR = Path(__file__).resolve().parent
if str(TEST_DIR) not in sys.path:
    sys.path.insert(0, str(TEST_DIR))
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "generate_store_style_update_sql.py"
PUBLISH_FIXTURE = PROJECT_ROOT / "tests" / "fixtures" / "virtual_store_publish_review.csv"

spec = importlib.util.spec_from_file_location("generate_store_style_update_sql", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
update_generator = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = update_generator
spec.loader.exec_module(update_generator)

from build_burger_style_review import STYLE_REVIEW_HEADERS
from style_review_test_utils import make_style_review_rows, write_style_review


class StoreStyleUpdateSqlTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.publish_path = self.temp_path / "publish-review.csv"
        self.style_path = self.temp_path / "style-review.csv"
        self.output_path = self.temp_path / "style-update.sql"
        shutil.copyfile(PUBLISH_FIXTURE, self.publish_path)

    @staticmethod
    def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            reader = csv.DictReader(input_file)
            return list(reader.fieldnames or []), list(reader)

    @staticmethod
    def write_csv(path: Path, headers, rows) -> None:
        with path.open("w", encoding="utf-8-sig", newline="") as output_file:
            writer = csv.DictWriter(output_file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)

    def write_style_rows(self, approved_numbers: set[int]) -> None:
        _, publish_rows = self.read_csv(self.publish_path)
        rows = make_style_review_rows(
            publish_rows,
            {1: "classic", 2: "chicken"},
            approved_numbers=approved_numbers,
        )
        write_style_review(self.style_path, STYLE_REVIEW_HEADERS, rows)

    def test_generates_one_guarded_update_for_verified_active_store(self) -> None:
        self.write_style_rows({1, 2})

        count = update_generator.generate_style_update_sql(
            self.style_path,
            self.publish_path,
            self.output_path,
        )
        sql = self.output_path.read_text(encoding="utf-8")

        self.assertEqual(count, 1)
        self.assertTrue(sql.startswith("begin;"))
        self.assertTrue(sql.endswith("commit;\n"))
        self.assertEqual(sql.lower().count("update public.stores"), 1)
        self.assertIn("set burger_style = 'classic'", sql)
        self.assertIn("11111111-1111-4111-8111-111111111111", sql)
        self.assertIn("verification_status = 'verified'", sql)
        self.assertIn("is_active = true", sql)
        self.assertIn("get diagnostics affected_rows = row_count", sql)
        self.assertIn("affected_rows <> 1", sql)
        self.assertIn("raise exception", sql)
        for forbidden in (
            "insert ",
            "delete ",
            "upsert",
            "rpc",
            "candidateId",
            "virtual_candidate_001",
            "evidenceUrl",
            "https://",
        ):
            self.assertNotIn(forbidden.lower(), sql.lower())

    def test_empty_target_stops_without_creating_sql(self) -> None:
        self.write_style_rows({2})

        with self.assertRaises(update_generator.NoStyleUpdatesError):
            update_generator.generate_style_update_sql(
                self.style_path,
                self.publish_path,
                self.output_path,
            )

        self.assertFalse(self.output_path.exists())

    def test_duplicate_publish_id_and_identity_mismatch_are_blocked(self) -> None:
        self.write_style_rows({1})
        headers, publish_rows = self.read_csv(self.publish_path)
        publish_rows[1]["storeId"] = publish_rows[0]["storeId"]
        self.write_csv(self.publish_path, headers, publish_rows)
        with self.assertRaises(update_generator.StorePublishingError):
            update_generator.generate_style_update_sql(
                self.style_path,
                self.publish_path,
                self.output_path,
            )
        self.assertFalse(self.output_path.exists())

        shutil.copyfile(PUBLISH_FIXTURE, self.publish_path)
        headers, publish_rows = self.read_csv(self.publish_path)
        publish_rows[0]["name"] = "다른 매장"
        self.write_csv(self.publish_path, headers, publish_rows)
        with self.assertRaises(update_generator.StorePublishingError):
            update_generator.generate_style_update_sql(
                self.style_path,
                self.publish_path,
                self.output_path,
            )
        self.assertFalse(self.output_path.exists())

    def test_failure_does_not_replace_existing_output(self) -> None:
        self.write_style_rows({2})
        self.output_path.write_text("existing-output", encoding="utf-8")

        with self.assertRaises(update_generator.NoStyleUpdatesError):
            update_generator.generate_style_update_sql(
                self.style_path,
                self.publish_path,
                self.output_path,
                overwrite=True,
            )

        self.assertEqual(self.output_path.read_text(encoding="utf-8"), "existing-output")


if __name__ == "__main__":
    unittest.main()
