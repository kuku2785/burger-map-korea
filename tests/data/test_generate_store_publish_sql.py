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
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "generate_store_publish_sql.py"
FIXTURE_PATH = (
    PROJECT_ROOT / "tests" / "fixtures" / "virtual_store_publish_review.csv"
)
MIGRATION_PATH = (
    PROJECT_ROOT / "supabase" / "migrations" / "0001_init_store_schema.sql"
)

spec = importlib.util.spec_from_file_location("generate_store_publish_sql", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
sql_generator = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = sql_generator
spec.loader.exec_module(sql_generator)

from build_burger_style_review import STYLE_REVIEW_HEADERS
from style_review_test_utils import make_style_review_rows, write_style_review


class StorePublishSqlGeneratorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.review_path = self.temp_path / "review.csv"
        self.output_path = self.temp_path / "publish.sql"
        self.style_path = self.temp_path / "style-review.csv"
        shutil.copyfile(FIXTURE_PATH, self.review_path)

    @staticmethod
    def read_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            reader = csv.DictReader(input_file)
            return list(reader.fieldnames or []), list(reader)

    @staticmethod
    def write_rows(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
        with path.open("w", encoding="utf-8-sig", newline="") as output_file:
            writer = csv.DictWriter(output_file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)

    def mutate(self, row_index: int, **values: str) -> None:
        headers, rows = self.read_rows(self.review_path)
        rows[row_index].update(values)
        self.write_rows(self.review_path, headers, rows)

    def generate(self, style_review_path: Path | None = None) -> int:
        return sql_generator.generate_publish_sql(
            self.review_path,
            MIGRATION_PATH,
            self.output_path,
            style_review_path,
        )

    def write_style_rows(
        self,
        styles: dict[int, str],
        *,
        approved_numbers: set[int] | None = None,
    ):
        _, publish_rows = self.read_rows(self.review_path)
        style_rows = make_style_review_rows(
            publish_rows,
            styles,
            approved_numbers=approved_numbers,
        )
        write_style_review(self.style_path, STYLE_REVIEW_HEADERS, style_rows)
        return style_rows

    def test_generates_transaction_for_verified_active_rows_only(self) -> None:
        count = self.generate()
        sql = self.output_path.read_text(encoding="utf-8")

        self.assertEqual(count, 1)
        self.assertTrue(sql.startswith("begin;"))
        self.assertTrue(sql.endswith("commit;\n"))
        self.assertIn("insert into public.stores", sql)
        self.assertIn("O''Brien Burger", sql)
        self.assertIn("Chef''s로 1", sql)
        self.assertIn("37.53403495783472", sql)
        self.assertIn("126.99249196362467", sql)
        self.assertNotIn("Pending Burger", sql)
        self.assertNotIn("virtual_candidate_001", sql)
        self.assertNotIn("candidateId", sql)
        self.assertNotIn("place_url", sql.lower())
        self.assertNotIn("http://", sql.lower())
        self.assertNotIn("https://", sql.lower())

    def test_zero_approved_rows_do_not_create_sql(self) -> None:
        self.mutate(
            0,
            publishDecision="pending",
            isActive="false",
            sourceAsOf="",
            verifiedAt="",
            verificationNote="",
        )

        with self.assertRaises(sql_generator.NoApprovedStoresError):
            self.generate()

        self.assertFalse(self.output_path.exists())

    def test_requires_complete_verification_evidence(self) -> None:
        for field in ("sourceAsOf", "verifiedAt", "verificationNote"):
            with self.subTest(field=field):
                shutil.copyfile(FIXTURE_PATH, self.review_path)
                self.mutate(0, **{field: ""})
                with self.assertRaises(sql_generator.StorePublishingError):
                    self.generate()
                self.assertFalse(self.output_path.exists())

    def test_rejects_invalid_coordinate_duplicate_uuid_state_and_source_type(self) -> None:
        cases = (
            (0, {"latitude": "91"}),
            (1, {"storeId": "11111111-1111-4111-8111-111111111111"}),
            (1, {"publishDecision": "approved"}),
            (1, {"sourceType": "kakao"}),
            (1, {"isActive": "true"}),
        )
        for row_index, values in cases:
            with self.subTest(values=values):
                shutil.copyfile(FIXTURE_PATH, self.review_path)
                self.mutate(row_index, **values)
                with self.assertRaises(sql_generator.StorePublishingError):
                    self.generate()
                self.assertFalse(self.output_path.exists())

    def test_rejects_suspected_duplicate_store(self) -> None:
        self.mutate(
            1,
            name=" O'Brien Burger ",
            address="서울 용산구 Chef's로 1",
        )

        with self.assertRaisesRegex(
            sql_generator.StorePublishingError,
            "중복 매장 의심",
        ):
            self.generate()

    def test_optional_style_review_applies_only_approved_style(self) -> None:
        self.write_style_rows(
            {1: "classic", 2: "chicken"},
            approved_numbers={1, 2},
        )

        count = self.generate(self.style_path)
        sql = self.output_path.read_text(encoding="utf-8")

        self.assertEqual(count, 1)
        self.assertIn("'classic'", sql)
        self.assertNotIn("'chicken'", sql)
        self.assertNotIn("Pending Burger", sql)
        self.assertNotIn("evidenceUrl", sql)

    def test_optional_style_review_keeps_unapproved_style_unclassified(self) -> None:
        self.write_style_rows({2: "chicken"}, approved_numbers={2})

        self.generate(self.style_path)
        sql = self.output_path.read_text(encoding="utf-8")

        self.assertIn("'unclassified'", sql)
        self.assertNotIn("'chicken'", sql)

    def test_optional_style_review_rejects_identity_mismatch(self) -> None:
        style_rows = self.write_style_rows({1: "classic"}, approved_numbers={1})
        style_rows[0]["address"] = "서울 용산구 다른로 99"
        write_style_review(self.style_path, STYLE_REVIEW_HEADERS, style_rows)

        with self.assertRaises(sql_generator.StorePublishingError):
            self.generate(self.style_path)

        self.assertFalse(self.output_path.exists())


if __name__ == "__main__":
    unittest.main()
