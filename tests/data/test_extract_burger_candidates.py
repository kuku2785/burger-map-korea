from __future__ import annotations

import csv
import io
import importlib.util
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "extract_burger_candidates.py"
FIXTURE_PATH = PROJECT_ROOT / "tests" / "fixtures" / "virtual_commercial_stores.csv"
SCREENING_FIXTURE_PATH = (
    PROJECT_ROOT / "tests" / "fixtures" / "virtual_screening_stores.csv"
)

spec = importlib.util.spec_from_file_location("extract_burger_candidates", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
extractor = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = extractor
spec.loader.exec_module(extractor)


class BurgerCandidateExtractorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.output_path = Path(self.temporary_directory.name) / "candidates.csv"

    def extract_fixture(self):
        stats = extractor.extract_candidates(
            input_path=FIXTURE_PATH,
            output_path=self.output_path,
            source_as_of="2026-03-31",
        )
        with self.output_path.open("r", encoding="utf-8-sig", newline="") as file:
            rows = list(csv.DictReader(file))
        return stats, rows

    @staticmethod
    def by_source_id(rows: list[dict[str, str]], source_id: str):
        return [row for row in rows if row["sourceStoreId"] == source_id]

    def test_filters_to_seoul_yongsan(self) -> None:
        stats, rows = self.extract_fixture()

        self.assertEqual(stats.total_input_rows, 14)
        self.assertEqual(stats.sido_rows, 13)
        self.assertEqual(stats.sigungu_rows, 12)
        self.assertFalse(self.by_source_id(rows, "V006"))
        self.assertFalse(self.by_source_id(rows, "V007"))

    def test_category_and_name_rules_are_combined_as_union(self) -> None:
        _, rows = self.extract_fixture()

        self.assertEqual(self.by_source_id(rows, "V001")[0]["candidateReason"], "category")
        self.assertEqual(self.by_source_id(rows, "V002")[0]["candidateReason"], "name")
        self.assertEqual(self.by_source_id(rows, "V004")[0]["candidateReason"], "category_and_name")
        self.assertFalse(self.by_source_id(rows, "V005"))

    def test_english_name_matching_is_case_insensitive(self) -> None:
        _, rows = self.extract_fixture()

        self.assertEqual(self.by_source_id(rows, "V003")[0]["candidateReason"], "name")

    def test_missing_required_value_is_needs_recheck(self) -> None:
        stats, rows = self.extract_fixture()
        candidate = self.by_source_id(rows, "V008")[0]

        self.assertGreaterEqual(stats.missing_required_rows, 1)
        self.assertEqual(candidate["verificationStatus"], "needs_recheck")
        self.assertIn("missing_required:address", candidate["verificationNote"])

    def test_invalid_and_zero_coordinates_are_needs_recheck(self) -> None:
        stats, rows = self.extract_fixture()
        invalid = self.by_source_id(rows, "V009")[0]
        zero = self.by_source_id(rows, "V010")[0]

        self.assertEqual(stats.invalid_coordinate_rows, 2)
        self.assertIn("invalid_coordinates_not_numeric", invalid["verificationNote"])
        self.assertIn("coordinates_zero_zero", zero["verificationNote"])
        self.assertEqual(invalid["verificationStatus"], "needs_recheck")
        self.assertEqual(zero["verificationStatus"], "needs_recheck")

    def test_duplicate_source_id_marks_all_related_rows(self) -> None:
        stats, rows = self.extract_fixture()
        duplicates = self.by_source_id(rows, "V011")

        self.assertEqual(len(duplicates), 2)
        self.assertGreaterEqual(stats.duplicate_or_suspected_rows, 2)
        self.assertTrue(
            all("duplicate_source_store_id" in row["verificationNote"] for row in duplicates)
        )
        self.assertTrue(
            all("duplicate_candidate_id" in row["verificationNote"] for row in duplicates)
        )

    def test_normalized_name_and_address_duplicate_marks_both_rows(self) -> None:
        _, rows = self.extract_fixture()
        duplicates = self.by_source_id(rows, "V012") + self.by_source_id(rows, "V013")

        self.assertEqual(len(duplicates), 2)
        self.assertTrue(
            all(
                "suspected_duplicate_name_address" in row["verificationNote"]
                for row in duplicates
            )
        )

    def test_candidate_ids_and_output_order_are_deterministic(self) -> None:
        _, first_rows = self.extract_fixture()
        first_bytes = self.output_path.read_bytes()
        second_output = Path(self.temporary_directory.name) / "second.csv"

        extractor.extract_candidates(
            input_path=FIXTURE_PATH,
            output_path=second_output,
            source_as_of="2026-03-31",
        )

        self.assertEqual(first_bytes, second_output.read_bytes())
        candidate_ids = [row["candidateId"] for row in first_rows]
        self.assertEqual(candidate_ids, sorted(candidate_ids))
        self.assertEqual(self.by_source_id(first_rows, "V001")[0]["candidateId"], "semas_V001")

    def test_default_values_never_auto_verify_candidates(self) -> None:
        _, rows = self.extract_fixture()

        self.assertTrue(
            all(row["verificationStatus"] in {"pending", "needs_recheck"} for row in rows)
        )
        self.assertTrue(all(row["verificationStatus"] != "verified" for row in rows))
        self.assertTrue(all(row["burgerStyle"] == "미분류" for row in rows))
        self.assertTrue(all(row["verifiedAt"] == "" for row in rows))

    def test_missing_source_store_id_is_counted_and_excluded(self) -> None:
        input_path = Path(self.temporary_directory.name) / "missing_source_id.csv"
        row = {
            header: ""
            for header in extractor.REQUIRED_HEADERS
        }
        row.update(
            {
                "상호명": "식별자없는 가상버거",
                "상권업종대분류명": "음식",
                "상권업종중분류명": "기타",
                "상권업종소분류명": "기타 음식",
                "시도명": "서울특별시",
                "시군구명": "용산구",
                "도로명주소": "서울특별시 용산구 가상로 99",
                "경도": "126.99",
                "위도": "37.53",
            }
        )
        with input_path.open("w", encoding="utf-8-sig", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=extractor.REQUIRED_HEADERS)
            writer.writeheader()
            writer.writerow(row)

        stats = extractor.extract_candidates(
            input_path=input_path,
            output_path=self.output_path,
            source_as_of="2026-03-31",
        )

        self.assertEqual(stats.missing_required_rows, 1)
        self.assertEqual(stats.excluded_rows, 1)
        self.assertEqual(stats.output_rows, 0)

    def test_truncated_row_is_reported_as_missing_instead_of_crashing(self) -> None:
        input_path = Path(self.temporary_directory.name) / "truncated_row.csv"
        with input_path.open("w", encoding="utf-8-sig", newline="") as file:
            writer = csv.writer(file)
            writer.writerow(extractor.REQUIRED_HEADERS)
            writer.writerow(
                [
                    "V099",
                    "잘린행 가상버거",
                    "",
                    "음식",
                    "기타",
                    "기타 음식",
                    "서울특별시",
                    "용산구",
                    "서울특별시 용산구 가상로 99",
                ]
            )

        stats = extractor.extract_candidates(
            input_path=input_path,
            output_path=self.output_path,
            source_as_of="2026-03-31",
        )
        with self.output_path.open("r", encoding="utf-8-sig", newline="") as file:
            candidate = next(csv.DictReader(file))

        self.assertEqual(stats.output_rows, 1)
        self.assertEqual(candidate["verificationStatus"], "needs_recheck")
        self.assertIn("missing_required:latitude,longitude", candidate["verificationNote"])
        self.assertIn("invalid_coordinates_not_numeric", candidate["verificationNote"])

    def test_missing_required_header_fails_with_missing_and_actual_headers(self) -> None:
        input_path = Path(self.temporary_directory.name) / "missing_header.csv"
        headers = [header for header in extractor.REQUIRED_HEADERS if header != "경도"]
        with input_path.open("w", encoding="utf-8", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=headers)
            writer.writeheader()

        with self.assertRaises(extractor.HeaderValidationError) as context:
            extractor.extract_candidates(
                input_path=input_path,
                output_path=self.output_path,
                source_as_of="2026-03-31",
            )

        message = str(context.exception)
        self.assertIn("경도", message)
        self.assertIn("실제 헤더", message)

    def test_cli_writes_output_and_prints_summary(self) -> None:
        stdout = io.StringIO()

        with redirect_stdout(stdout):
            exit_code = extractor.main(
                [
                    "--input",
                    str(FIXTURE_PATH),
                    "--output",
                    str(self.output_path),
                    "--source-as-of",
                    "2026-03-31",
                    "--sido",
                    "서울특별시",
                    "--sigungu",
                    "용산구",
                ]
            )

        summary = stdout.getvalue()
        self.assertEqual(exit_code, 0)
        self.assertTrue(self.output_path.exists())
        self.assertIn("전체 입력 행 수", summary)
        self.assertIn("category_and_name 후보 수", summary)
        self.assertIn("최종 출력 경로", summary)


class BurgerCandidateScreeningTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.output_path = Path(self.temporary_directory.name) / "screened.csv"
        extractor.extract_candidates(
            input_path=SCREENING_FIXTURE_PATH,
            output_path=self.output_path,
            source_as_of="2026-06-30",
        )
        with self.output_path.open(
            "r", encoding="utf-8-sig", newline=""
        ) as file:
            self.rows = list(csv.DictReader(file))

    def candidate(self, source_id: str) -> dict[str, str]:
        return next(
            row for row in self.rows if row["sourceStoreId"] == source_id
        )

    def test_brand_alias_finds_store_without_burger_name_or_category(self) -> None:
        candidate = self.candidate("S001")

        self.assertEqual(candidate["name"], "빌리언－박스")
        self.assertEqual(candidate["candidateReason"], "brand_alias")
        self.assertEqual(candidate["verificationStatus"], "pending")

    def test_pizza_specialty_rule_prevents_pending_approval_candidate(self) -> None:
        candidate = self.candidate("S002")

        self.assertEqual(candidate["exclusionReason"], "pizza_specialty")
        self.assertEqual(candidate["verificationStatus"], "needs_recheck")

    def test_rice_burger_is_not_screened_as_regular_burger(self) -> None:
        candidate = self.candidate("S003")

        self.assertEqual(candidate["exclusionReason"], "rice_burger")
        self.assertEqual(candidate["verificationStatus"], "needs_recheck")

    def test_large_fast_food_chain_is_flagged(self) -> None:
        candidate = self.candidate("S004")

        self.assertEqual(
            candidate["exclusionReason"], "large_fast_food_chain"
        )
        self.assertEqual(candidate["verificationStatus"], "needs_recheck")

    def test_english_burger_name_ignores_case_spaces_and_parentheses(self) -> None:
        candidate = self.candidate("S005")

        self.assertEqual(candidate["candidateReason"], "name")
        self.assertEqual(candidate["verificationStatus"], "pending")

    def test_alias_candidates_are_never_automatically_verified(self) -> None:
        alias_candidates = [
            row for row in self.rows if "alias" in row["candidateReason"]
        ]

        self.assertTrue(alias_candidates)
        self.assertTrue(
            all(row["verificationStatus"] != "verified" for row in alias_candidates)
        )
        self.assertTrue(all(row["verifiedAt"] == "" for row in alias_candidates))

    def test_config_distinguishes_required_exclusion_rule_types(self) -> None:
        rules = extractor.load_exclusion_rules(
            extractor.DEFAULT_EXCLUSION_RULES_PATH
        )
        rule_ids = {str(rule["id"]) for rule in rules}

        self.assertTrue(
            {
                "large_fast_food_chain",
                "pizza_specialty",
                "rice_burger",
                "obvious_non_burger_restaurant",
            }.issubset(rule_ids)
        )

    def test_all_candidate_reason_combinations_are_supported(self) -> None:
        aliases = frozenset({extractor.normalize_name_for_matching("가상상점")})

        def reason(category: str, name: str) -> str | None:
            row = {
                "상호명": name,
                "지점명": "",
                "상권업종대분류명": "음식",
                "상권업종중분류명": "기타",
                "상권업종소분류명": category,
            }
            return extractor.candidate_reason(row, aliases)

        self.assertEqual(reason("기타 음식", "가상상점"), "brand_alias")
        self.assertEqual(reason("버거", "가상상점"), "category_and_alias")
        self.assertEqual(reason("기타 음식", "가상상점 burger"), "name")

        name_aliases = frozenset(
            {extractor.normalize_name_for_matching("가상버거")}
        )
        alias_name_row = {
            "상호명": "가상버거",
            "지점명": "",
            "상권업종대분류명": "음식",
            "상권업종중분류명": "기타",
            "상권업종소분류명": "기타 음식",
        }
        self.assertEqual(
            extractor.candidate_reason(alias_name_row, name_aliases),
            "name_and_alias",
        )
        alias_name_row["상권업종소분류명"] = "버거"
        self.assertEqual(
            extractor.candidate_reason(alias_name_row, name_aliases),
            "category_name_and_alias",
        )


if __name__ == "__main__":
    unittest.main()
