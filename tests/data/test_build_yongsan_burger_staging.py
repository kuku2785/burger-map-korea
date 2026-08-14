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
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "build_yongsan_burger_staging.py"

spec = importlib.util.spec_from_file_location("build_yongsan_burger_staging", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Cannot load script: {SCRIPT_PATH}")
staging = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = staging
spec.loader.exec_module(staging)


class YongsanBurgerStagingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.v2_path = self.temp_path / "v2.csv"
        self.reviewed_path = self.temp_path / "reviewed.csv"
        self.kakao_path = self.temp_path / "kakao_reviewed.csv"
        self.recheck_path = self.temp_path / "address_recheck.csv"
        self.hold_rules_path = self.temp_path / "hold_rules.json"
        self.empty_resolutions_path = self.temp_path / "empty_resolutions.json"
        self.staging_output = self.temp_path / "staging.csv"
        self.hold_output = self.temp_path / "hold.csv"
        self._write_fixture_inputs()

    @staticmethod
    def write_csv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
        with path.open("w", encoding="utf-8-sig", newline="") as output_file:
            writer = csv.DictWriter(output_file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)

    @staticmethod
    def read_rows(path: Path) -> list[dict[str, str]]:
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            return list(csv.DictReader(input_file))

    def _write_fixture_inputs(self) -> None:
        semas_rows = []
        for index in range(1, 15):
            semas_rows.append(
                {
                    "candidateId": f"semas_SYN_LINK_{index:02d}",
                    "sourceStoreId": f"SYN_STORE_{index:02d}",
                    "name": f"가상 링크 버거 {index:02d}",
                    "address": f"서울 용산구 가상로 {index}",
                    "latitude": f"{37.5100 + index / 1000:.4f}",
                    "longitude": f"{126.9600 + index / 1000:.4f}",
                    "verificationStatus": "pending",
                }
            )
        for index in range(1, 3):
            semas_rows.append(
                {
                    "candidateId": f"semas_SYN_HOLD_{index:02d}",
                    "sourceStoreId": f"SYN_HOLD_STORE_{index:02d}",
                    "name": f"가상 상가 보류 {index:02d}",
                    "address": f"서울 용산구 보류로 {index}",
                    "latitude": f"{37.5300 + index / 1000:.4f}",
                    "longitude": f"{126.9800 + index / 1000:.4f}",
                    "verificationStatus": "pending",
                }
            )
        headers = list(semas_rows[0])
        self.write_csv(self.v2_path, headers, semas_rows)
        self.write_csv(self.reviewed_path, headers, semas_rows)

        kakao_rows = []
        for index in range(1, 15):
            kakao_rows.append(
                {
                    "sourcePlaceId": f"SYN_PLACE_LINK_{index:02d}",
                    "name": f"가상 링크 버거 {index:02d}",
                    "address": f"서울 용산구 가상로 {index}",
                    "latitude": f"{37.5100 + index / 1000:.4f}",
                    "longitude": f"{126.9600 + index / 1000:.4f}",
                    "sourceCategory": "음식점 > 햄버거",
                    "placeUrl": f"https://example.invalid/place/link-{index:02d}",
                    "matchedCandidateId": f"semas_SYN_LINK_{index:02d}",
                    "manualReviewStatus": "pending",
                    "manualReviewAction": "link_existing",
                }
            )
        for index in range(1, 11):
            kakao_rows.append(
                {
                    "sourcePlaceId": f"SYN_PLACE_ADD_{index:02d}",
                    "name": f"가상 신규 버거 {index:02d}",
                    "address": f"서울 용산구 신규로 {index}",
                    "latitude": f"{37.5400 + index / 1000:.4f}",
                    "longitude": f"{126.9900 + index / 1000:.4f}",
                    "sourceCategory": "음식점 > 햄버거",
                    "placeUrl": f"https://example.invalid/place/add-{index:02d}",
                    "matchedCandidateId": "",
                    "manualReviewStatus": "pending",
                    "manualReviewAction": "add_pending",
                }
            )
        for index in range(1, 3):
            kakao_rows.append(
                {
                    "sourcePlaceId": f"SYN_PLACE_HOLD_{index:02d}",
                    "name": f"가상 주소 보류 {index:02d}",
                    "address": f"서울 용산구 확인로 {index}",
                    "latitude": f"{37.5500 + index / 1000:.4f}",
                    "longitude": f"{127.0000 + index / 1000:.4f}",
                    "sourceCategory": "음식점 > 햄버거",
                    "placeUrl": f"https://example.invalid/place/hold-{index:02d}",
                    "matchedCandidateId": "",
                    "manualReviewStatus": "needs_recheck",
                    "manualReviewAction": "needs_address_check",
                }
            )
        self.write_csv(self.kakao_path, list(kakao_rows[0]), kakao_rows)

        recheck_rows = [
            {
                "targetName": f"가상 주소 보류 {index:02d}",
                "previousSourcePlaceId": f"SYN_PLACE_HOLD_{index:02d}",
                "recheckDecision": "needs_manual_check",
            }
            for index in range(1, 3)
        ]
        self.write_csv(self.recheck_path, list(recheck_rows[0]), recheck_rows)

        holds = [
            {
                "candidateId": f"kakao_SYN_PLACE_HOLD_{index:02d}",
                "sourcePlaceId": f"SYN_PLACE_HOLD_{index:02d}",
                "expectedName": f"가상 주소 보류 {index:02d}",
                "holdReason": "합성 주소 재확인",
                "recommendedAction": "수동 확인",
            }
            for index in range(1, 3)
        ]
        holds.extend(
            {
                "candidateId": f"semas_SYN_HOLD_{index:02d}",
                "sourcePlaceId": "",
                "expectedName": f"가상 상가 보류 {index:02d}",
                "holdReason": "합성 영업 상태 재확인",
                "recommendedAction": "수동 확인",
            }
            for index in range(1, 3)
        )
        self.hold_rules_path.write_text(
            json.dumps({"version": 1, "holds": holds}, ensure_ascii=False),
            encoding="utf-8",
        )
        self.empty_resolutions_path.write_text(
            json.dumps({"version": 1, "resolutions": []}),
            encoding="utf-8",
        )

    def generate(self, address_resolutions_path: Path | None = None):
        return staging.generate_staging(
            v2_path=self.v2_path,
            reviewed_path=self.reviewed_path,
            kakao_reviewed_path=self.kakao_path,
            address_recheck_path=self.recheck_path,
            hold_rules_path=self.hold_rules_path,
            address_resolutions_path=(
                address_resolutions_path or self.empty_resolutions_path
            ),
            staging_output_path=self.staging_output,
            hold_output_path=self.hold_output,
        )

    def write_resolution_config(
        self,
        *,
        candidate_id: str = "semas_SYN_LINK_01",
        source_place_id: str = "SYN_PLACE_LINK_01",
    ) -> Path:
        data = {
            "version": 1,
            "resolutions": [
                {
                    "candidateId": candidate_id,
                    "sourcePlaceId": source_place_id,
                    "sourceAddress": "서울 용산구 가상로 1",
                    "displayAddress": "서울 용산구 변경로 1",
                    "lotAddress": "서울 용산구 가상동 1",
                    "buildingName": "가상 건물",
                    "resolutionStatus": "resolved_same_building_variant",
                    "resolutionNote": "합성 fixture의 동일 건물 주소 변형 판정.",
                }
            ],
        }
        output = self.temp_path / f"resolutions_{candidate_id}_{source_place_id}.json"
        output.write_text(
            json.dumps(data, ensure_ascii=False),
            encoding="utf-8",
        )
        return output

    def set_first_link_address(self, address: str) -> None:
        rows = self.read_rows(self.kakao_path)
        rows[0]["address"] = address
        self.write_csv(self.kakao_path, list(rows[0]), rows)

    def test_fixture_has_exactly_24_eligible_rows(self) -> None:
        inputs = staging.load_inputs(
            self.v2_path,
            self.reviewed_path,
            self.kakao_path,
            self.recheck_path,
        )
        rows = staging.included_kakao_rows(inputs.kakao_rows)

        self.assertEqual(len(rows), 24)
        self.assertEqual(
            Counter(row["manualReviewAction"] for row in rows),
            Counter({"link_existing": 14, "add_pending": 10}),
        )

    def test_generation_builds_24_staging_and_four_holds(self) -> None:
        staging_rows, hold_rows = self.generate()

        self.assertEqual(len(staging_rows), 24)
        self.assertEqual(len(hold_rows), 4)
        self.assertEqual(
            Counter(row["sourceType"] for row in staging_rows),
            Counter({"semas_kakao": 14, "kakao": 10}),
        )
        self.assertEqual(len({row["candidateId"] for row in staging_rows}), 24)
        self.assertEqual(len({row["sourcePlaceId"] for row in staging_rows}), 24)
        self.assertTrue(
            all(row["verificationStatus"] == "pending" for row in staging_rows)
        )
        self.assertTrue(
            all(row["stagingStatus"] == "hold_needs_recheck" for row in hold_rows)
        )

    def test_address_conflict_stops_staging_but_writes_hold_report(self) -> None:
        self.set_first_link_address("서울 용산구 변경로 1")

        with self.assertRaises(staging.AddressConflictError):
            self.generate()

        self.assertFalse(self.staging_output.exists())
        self.assertEqual(len(self.read_rows(self.hold_output)), 4)

    def test_resolution_requires_both_candidate_and_source_place_ids(self) -> None:
        self.set_first_link_address("서울 용산구 변경로 1")
        exact = self.write_resolution_config()
        rows, _ = self.generate(exact)
        self.assertEqual(rows[0]["address"], "서울 용산구 변경로 1")
        self.assertEqual(
            rows[0]["addressConflict"], "resolved_same_building_variant"
        )

        for candidate_id, source_place_id in (
            ("semas_SYN_DIFFERENT", "SYN_PLACE_LINK_01"),
            ("semas_SYN_LINK_01", "SYN_PLACE_DIFFERENT"),
        ):
            with self.subTest(candidate_id=candidate_id, source_place_id=source_place_id):
                self.staging_output = self.temp_path / f"staging_{source_place_id}.csv"
                self.hold_output = self.temp_path / f"hold_{source_place_id}.csv"
                config = self.write_resolution_config(
                    candidate_id=candidate_id,
                    source_place_id=source_place_id,
                )
                with self.assertRaises(staging.AddressConflictError):
                    self.generate(config)

    def test_validation_rejects_bad_rows_and_hold_candidates(self) -> None:
        rows, hold_rows = self.generate()
        cases = {
            "duplicate candidate": (0, "candidateId", rows[1]["candidateId"]),
            "missing coordinate": (0, "latitude", ""),
            "verified": (0, "verificationStatus", "verified"),
            "rejected": (0, "verificationStatus", "rejected"),
            "needs recheck": (0, "verificationStatus", "needs_recheck"),
        }
        forbidden_ids = {row["candidateId"] for row in hold_rows}
        for label, (index, field, value) in cases.items():
            with self.subTest(label=label):
                changed = [dict(row) for row in rows]
                changed[index][field] = value
                with self.assertRaises(staging.StagingError):
                    staging.validate_staging_rows(changed, forbidden_ids)

        changed = [dict(row) for row in rows]
        changed[0]["candidateId"] = next(iter(forbidden_ids))
        with self.assertRaises(staging.StagingError):
            staging.validate_staging_rows(changed, forbidden_ids)


if __name__ == "__main__":
    unittest.main()
