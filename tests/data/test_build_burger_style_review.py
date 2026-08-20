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
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "build_burger_style_review.py"

spec = importlib.util.spec_from_file_location("build_burger_style_review", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
review_builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = review_builder
spec.loader.exec_module(review_builder)


class BurgerStyleReviewBuilderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.staging_path = self.temp_path / "staging.csv"
        self.publish_path = self.temp_path / "publish_review.csv"
        self.hold_path = self.temp_path / "hold.csv"
        self.output_path = self.temp_path / "style_review.csv"
        self.staging_headers = [
            "candidateId",
            "displayName",
            "address",
            "latitude",
            "longitude",
            "stagingStatus",
            "verificationStatus",
        ]
        self.publish_headers = [
            "storeId",
            "candidateId",
            "name",
            "address",
            "latitude",
            "longitude",
            "burgerStyle",
        ]
        self.hold_headers = ["candidateId", "name", "stagingStatus"]
        self.staging_rows = []
        self.publish_rows = []
        for index in range(1, 25):
            candidate_id = f"virtual_candidate_{index:03d}"
            name = f"가상 버거 매장 {index}"
            address = f"서울 가상구 테스트로 {index}"
            latitude = f"{37.50 + index / 1000:.3f}"
            longitude = f"{126.90 + index / 1000:.3f}"
            self.staging_rows.append(
                {
                    "candidateId": candidate_id,
                    "displayName": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                    "stagingStatus": "candidate_pending",
                    "verificationStatus": "pending",
                }
            )
            self.publish_rows.append(
                {
                    "storeId": str(
                        uuid.UUID(f"00000000-0000-4000-8000-{index:012d}")
                    ),
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                    "burgerStyle": "미분류" if index > 1 else "CLASSIC",
                }
            )
        self.hold_rows = [
            {
                "candidateId": f"hold-{index}",
                "name": f"가상 보류 매장 {index}",
                "stagingStatus": "hold_needs_recheck",
            }
            for index in range(1, 5)
        ]
        self.write_inputs()

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

    def write_inputs(self) -> None:
        self.write_csv(self.staging_path, self.staging_headers, self.staging_rows)
        self.write_csv(self.publish_path, self.publish_headers, self.publish_rows)
        self.write_csv(self.hold_path, self.hold_headers, self.hold_rows)

    def generate(self):
        return review_builder.generate_style_review(
            self.staging_path,
            self.publish_path,
            self.hold_path,
            self.output_path,
        )

    def test_generates_24_safe_rows_in_input_order_without_approval(self) -> None:
        input_hashes = {
            path: self.sha256(path)
            for path in (self.staging_path, self.publish_path, self.hold_path)
        }

        rows = self.generate()

        self.assertEqual(len(rows), 24)
        self.assertEqual([row["reviewNumber"] for row in rows], [str(i) for i in range(1, 25)])
        self.assertEqual(
            [row["candidateId"] for row in rows],
            [row["candidateId"] for row in self.staging_rows],
        )
        self.assertEqual(len({row["storeId"] for row in rows}), 24)
        self.assertEqual(
            self.read_csv(self.output_path)[0],
            list(review_builder.STYLE_REVIEW_HEADERS),
        )
        self.assertNotIn("latitude", rows[0])
        self.assertNotIn("longitude", rows[0])
        self.assertTrue(all(row["reviewStatus"] == "needs_recheck" for row in rows))
        self.assertTrue(all(row["proposedBurgerStyle"] == "unclassified" for row in rows))
        self.assertTrue(all(row["confidence"] == "low" for row in rows))
        self.assertTrue(all(row["sourceAgreement"] == "unavailable" for row in rows))
        self.assertTrue(
            all(
                row["approvalRecommendation"] == "needs_manual_check"
                for row in rows
            )
        )
        self.assertFalse(any(row["reviewStatus"] == "approved" for row in rows))
        self.assertEqual(rows[0]["currentBurgerStyle"], "classic")
        self.assertTrue(all(row["currentBurgerStyle"] == "unclassified" for row in rows[1:]))
        self.assertEqual(
            input_hashes,
            {
                path: self.sha256(path)
                for path in (self.staging_path, self.publish_path, self.hold_path)
            },
        )

    def test_preserves_human_review_fields_and_is_byte_stable(self) -> None:
        self.generate()
        headers, rows = self.read_csv(self.output_path)
        rows[0].update(
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "approved",
                "confidence": "high",
                "evidenceSourceType": "official_website",
                "evidenceSourceName": "가상 공식 메뉴",
                "evidenceUrl": "https://example.com/menu",
                "evidenceCheckedAt": "2026-08-20",
                "evidenceNote": "가상 근거",
                "reviewerNote": "사용자 승인",
                "sourceAgreement": "consistent",
                "freshnessNote": "2026-08-20 공식 페이지 확인.",
                "approvalRecommendation": "ready_for_user_approval",
            }
        )
        self.write_csv(self.output_path, headers, rows)
        expected_hash = self.sha256(self.output_path)

        refreshed = self.generate()

        self.assertEqual(refreshed[0]["reviewStatus"], "approved")
        self.assertEqual(refreshed[0]["reviewerNote"], "사용자 승인")
        self.assertEqual(self.sha256(self.output_path), expected_hash)

    def test_blocks_hold_store_duplicate_ids_and_invalid_coordinates(self) -> None:
        mutations = (
            lambda: self.staging_rows[0].update(
                candidateId=self.hold_rows[0]["candidateId"],
                displayName=self.hold_rows[0]["name"],
            ),
            lambda: self.staging_rows[1].update(
                candidateId=self.staging_rows[0]["candidateId"]
            ),
            lambda: self.staging_rows[0].update(latitude="91"),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.setUp()
                mutation()
                self.write_inputs()
                with self.assertRaises(review_builder.StorePublishingError):
                    self.generate()

    def test_blocks_added_or_removed_store_and_changed_publish_identity(self) -> None:
        with self.subTest("removed"):
            self.publish_rows.pop()
            self.write_inputs()
            with self.assertRaises(review_builder.StorePublishingError):
                self.generate()

        self.setUp()
        with self.subTest("changed immutable value"):
            self.publish_rows[0]["address"] = "변경된 주소"
            self.write_inputs()
            with self.assertRaises(review_builder.StorePublishingError):
                self.generate()

    def test_blocks_changed_existing_immutable_fields_and_invalid_review_values(self) -> None:
        self.generate()
        headers, rows = self.read_csv(self.output_path)
        cases = (
            {"storeId": str(uuid.uuid4())},
            {"proposedBurgerStyle": "unknown"},
            {"proposedBurgerStyle": "unclassified", "reviewStatus": "proposed"},
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "proposed",
                "confidence": "low",
                "sourceAgreement": "consistent",
                "approvalRecommendation": "ready_for_user_approval",
            },
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "proposed",
                "confidence": "high",
                "evidenceSourceType": "crowd_blog",
                "evidenceSourceName": "가상 출처",
                "evidenceUrl": "https://example.com/menu",
                "evidenceCheckedAt": "2026-08-20",
                "evidenceNote": "가상 근거",
                "sourceAgreement": "consistent",
                "approvalRecommendation": "ready_for_user_approval",
            },
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "proposed",
                "confidence": "high",
                "sourceAgreement": "consistent",
                "approvalRecommendation": "ready_for_user_approval",
            },
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "proposed",
                "confidence": "medium",
                "evidenceSourceType": "place_platform",
                "evidenceSourceName": "가상 장소 페이지",
                "evidenceUrl": "https://example.com/menu",
                "evidenceCheckedAt": "2026-08-20",
                "evidenceNote": "가상 근거",
                "sourceAgreement": "single_source",
                "approvalRecommendation": "ready_for_user_approval",
            },
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "proposed",
                "confidence": "medium",
                "evidenceSourceType": "place_platform",
                "evidenceSourceName": "가상 장소 페이지",
                "evidenceUrl": "https://example.com/menu",
                "evidenceCheckedAt": "2026-08-20",
                "evidenceNote": "가상 근거",
                "secondaryEvidenceSourceType": "article",
                "secondaryEvidenceSourceName": "가상 기사",
                "secondaryEvidenceUrl": "https://example.org/article",
                "sourceAgreement": "conflict",
                "approvalRecommendation": "ready_for_user_approval",
            },
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "proposed",
                "confidence": "medium",
                "evidenceSourceType": "official_website",
                "evidenceSourceName": "가상 공식 페이지",
                "evidenceUrl": "https://example.com/menu",
                "evidenceCheckedAt": "2026-08-20",
                "evidenceNote": "가상 근거",
                "sourceAgreement": "consistent",
                "approvalRecommendation": "needs_manual_check",
            },
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "approved",
                "confidence": "high",
                "evidenceSourceType": "official_website",
                "evidenceSourceName": "가상 공식 페이지",
                "evidenceUrl": "https://example.com/menu",
                "evidenceCheckedAt": "2026-08-20",
                "evidenceNote": "가상 근거",
                "reviewerNote": "",
                "sourceAgreement": "consistent",
                "approvalRecommendation": "ready_for_user_approval",
            },
        )
        for values in cases:
            with self.subTest(values=values):
                self.write_csv(self.output_path, headers, rows)
                current_headers, current_rows = self.read_csv(self.output_path)
                current_rows[0].update(values)
                self.write_csv(self.output_path, current_headers, current_rows)
                with self.assertRaises(review_builder.StorePublishingError):
                    self.generate()

    def test_does_not_leave_partial_output_after_validation_error(self) -> None:
        self.staging_rows[0]["latitude"] = "91"
        self.write_inputs()

        with self.assertRaises(review_builder.StorePublishingError):
            self.generate()

        self.assertFalse(self.output_path.exists())

    def test_migrates_legacy_coordinate_columns_without_losing_review(self) -> None:
        self.generate()
        headers, rows = self.read_csv(self.output_path)
        legacy_headers = list(review_builder.LEGACY_STYLE_REVIEW_HEADERS)
        legacy_rows = []
        for index, row in enumerate(rows):
            legacy_row = {
                header: row.get(header, "")
                for header in review_builder.B1_STYLE_REVIEW_HEADERS
            }
            legacy_row["latitude"] = self.staging_rows[index]["latitude"]
            legacy_row["longitude"] = self.staging_rows[index]["longitude"]
            legacy_rows.append(legacy_row)
        legacy_rows[0].update(
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "proposed",
                "confidence": "medium",
                "evidenceSourceType": "official_website",
                "evidenceSourceName": "가상 공식 페이지",
                "evidenceUrl": "https://example.com/menu",
                "evidenceCheckedAt": "2026-08-20",
                "evidenceNote": "가상 근거",
            }
        )
        self.assertNotEqual(headers, legacy_headers)
        self.write_csv(self.output_path, legacy_headers, legacy_rows)

        refreshed = self.generate()

        self.assertEqual(refreshed[0]["proposedBurgerStyle"], "unclassified")
        self.assertEqual(refreshed[0]["reviewStatus"], "needs_recheck")
        self.assertEqual(refreshed[0]["sourceAgreement"], "single_source")
        self.assertEqual(
            refreshed[0]["approvalRecommendation"], "needs_manual_check"
        )
        self.assertEqual(refreshed[0]["evidenceNote"], "가상 근거")
        self.assertIn("이전 제안: classic", refreshed[0]["reviewerNote"])
        refreshed_headers, _ = self.read_csv(self.output_path)
        self.assertEqual(refreshed_headers, list(review_builder.STYLE_REVIEW_HEADERS))

    def test_preserves_secondary_evidence_fields(self) -> None:
        self.generate()
        headers, rows = self.read_csv(self.output_path)
        rows[0].update(
            {
                "proposedBurgerStyle": "classic",
                "reviewStatus": "proposed",
                "confidence": "medium",
                "evidenceSourceType": "place_platform",
                "evidenceSourceName": "가상 메뉴 페이지",
                "evidenceUrl": "https://example.com/menu",
                "evidenceCheckedAt": "2026-08-20",
                "evidenceNote": "두 출처가 클래식 메뉴를 뒷받침함.",
                "secondaryEvidenceSourceType": "article",
                "secondaryEvidenceSourceName": "가상 기사",
                "secondaryEvidenceUrl": "https://example.org/article",
                "sourceAgreement": "consistent",
                "freshnessNote": "2026-08-20 두 페이지 확인.",
                "approvalRecommendation": "ready_for_user_approval",
            }
        )
        self.write_csv(self.output_path, headers, rows)

        refreshed = self.generate()

        self.assertEqual(
            refreshed[0]["secondaryEvidenceUrl"], "https://example.org/article"
        )
        self.assertEqual(refreshed[0]["sourceAgreement"], "consistent")
        self.assertEqual(
            refreshed[0]["approvalRecommendation"], "ready_for_user_approval"
        )


if __name__ == "__main__":
    unittest.main()
