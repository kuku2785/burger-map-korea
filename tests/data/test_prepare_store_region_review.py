from __future__ import annotations

import csv
import hashlib
import json
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = PROJECT_ROOT / "scripts" / "data"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import prepare_store_region_review as review  # noqa: E402


UUID_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
UUID_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
UUID_C = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
HEADERS = [
    "storeId",
    "candidateId",
    "name",
    "address",
    "burgerStyle",
    "sourceAsOf",
    "publishDecision",
    "isActive",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PrepareStoreRegionReviewTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.publish = self.root / "publish.csv"
        self.evidence_dir = self.root / "evidence"
        self.output = self.root / "output"
        self.publish_rows = [
            self.publish_row(UUID_A, "candidate-a", "Alpha Burger", "서울 용산구 길 10"),
            self.publish_row(UUID_B, "candidate-b", "Beta Burger", "서울 용산구 길 20 1층"),
            self.publish_row(
                UUID_C,
                "candidate-pending",
                "Pending Burger",
                "서울 용산구 길 30",
                decision="pending",
                active="false",
            ),
        ]
        self.evidence_rows = [
            self.evidence_row(
                UUID_A,
                "candidate-a",
                "Alpha Burger",
                "서울 용산구 길 10",
            ),
            self.evidence_row(
                UUID_B,
                "candidate-b",
                "Beta Burger",
                "서울 용산구 길 20 1층",
                candidate_address="서울 용산구 길 20",
                status="candidate_needs_review",
                issue_codes=["ADDRESS_NOT_EXACT"],
            ),
        ]
        self.write_inputs()

    @staticmethod
    def publish_row(
        store_id: str,
        candidate_id: str,
        name: str,
        address: str,
        *,
        decision: str = "verified",
        active: str = "true",
    ) -> dict[str, str]:
        return {
            "storeId": store_id,
            "candidateId": candidate_id,
            "name": name,
            "address": address,
            "burgerStyle": "",
            "sourceAsOf": "2026-08-25",
            "publishDecision": decision,
            "isActive": active,
        }

    @staticmethod
    def evidence_row(
        store_id: str,
        candidate_id: str,
        name: str,
        query_address: str,
        *,
        candidate_address: str | None = None,
        status: str = "exact_address_region_evidence",
        issue_codes: list[str] | None = None,
    ) -> dict[str, object]:
        candidate_address = candidate_address or query_address
        issues = [] if issue_codes is None else issue_codes
        return {
            "storeId": store_id,
            "candidateId": candidate_id,
            "name": name,
            "queryAddress": query_address,
            "manualReviewRequired": True,
            "storeExistenceVerified": False,
            "status": status,
            "totalCount": 1,
            "returnedCount": 1,
            "isEnd": True,
            "candidates": [
                {
                    "address_name": "서울 용산구 법정동 1",
                    "road_address_name": candidate_address,
                    "region_1depth_name": "서울",
                    "region_2depth_name": "용산구",
                    "region_3depth_name": "후암동",
                    "region_3depth_h_name": "남영동",
                    "b_code": "1117010100",
                    "h_code": "1117053000",
                    "issueCodes": issues,
                }
            ],
            "retrievedAt": "2026-09-14T02:40:41+00:00",
        }

    def write_inputs(self) -> None:
        with self.publish.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=HEADERS)
            writer.writeheader()
            writer.writerows(self.publish_rows)
        self.evidence_dir.mkdir(exist_ok=True)
        (self.evidence_dir / review.EVIDENCE_NAME).write_text(
            "".join(
                json.dumps(row, ensure_ascii=False) + "\n" for row in self.evidence_rows
            ),
            encoding="utf-8",
        )
        status_counts: dict[str, int] = {}
        for row in self.evidence_rows:
            status = str(row["status"])
            status_counts[status] = status_counts.get(status, 0) + 1
        summary = {
            "source": {"path": str(self.publish), "sha256": sha256(self.publish)},
            "sourceUnchanged": True,
            "completed": True,
            "remoteSupabaseChecked": False,
            "publishReady": False,
            "approvedTargetRows": 2,
            "statusCounts": status_counts,
            "collectedAt": "2026-09-14T02:41:00+00:00",
            "endpoint": "https://example.invalid/address",
            "documentation": "https://example.invalid/docs",
            "queryOptions": {"analyze_type": "exact", "size": 10},
            "automaticRetries": 0,
        }
        (self.evidence_dir / review.SUMMARY_NAME).write_text(
            json.dumps(summary, ensure_ascii=False), encoding="utf-8"
        )

    def run_review(self) -> tuple[dict[str, object], dict[str, object]]:
        summary = review.prepare_review_package(
            self.publish, self.evidence_dir, self.output
        )
        package = json.loads(
            (self.output / review.REVIEW_NAME).read_text(encoding="utf-8")
        )
        return summary, package

    def assert_no_output(self) -> None:
        self.assertFalse(self.output.exists())

    def test_valid_mapping_is_review_only_and_pending_publish_row_is_not_a_target(
        self,
    ) -> None:
        source_before = {
            self.publish: self.publish.read_bytes(),
            self.evidence_dir
            / review.SUMMARY_NAME: (
                self.evidence_dir / review.SUMMARY_NAME
            ).read_bytes(),
            self.evidence_dir
            / review.EVIDENCE_NAME: (
                self.evidence_dir / review.EVIDENCE_NAME
            ).read_bytes(),
        }

        summary, package = self.run_review()

        self.assertEqual(
            summary["counts"],
            {
                "publishRows": 3,
                "approvedTargetRows": 2,
                "reviewCandidateRows": 1,
                "excludedRows": 1,
            },
        )
        candidate = package["reviewCandidates"][0]
        self.assertEqual(candidate["candidateId"], "candidate-a")
        self.assertEqual(
            candidate["preconditions"],
            {
                "id": UUID_A,
                "name": "Alpha Burger",
                "address": "서울 용산구 길 10",
                "verification_status": "verified",
                "is_active": True,
            },
        )
        self.assertEqual(set(candidate["proposedUpdate"]), {"region"})
        self.assertEqual(
            candidate["proposedUpdate"]["region"]["dongCode"], "1117010100"
        )
        self.assertNotEqual(
            candidate["proposedUpdate"]["region"]["dongCode"], "1117053000"
        )
        self.assertTrue(candidate["manualReviewRequired"])
        self.assertFalse(candidate["publishReady"])
        self.assertFalse(candidate["remoteSupabaseChecked"])
        self.assertEqual(package["excluded"][0]["candidateId"], "candidate-b")
        self.assertIn(
            "EVIDENCE_ADDRESS_NOT_EXACT", package["excluded"][0]["reasonCodes"]
        )
        self.assertNotIn("candidate-pending", json.dumps(package))
        self.assertEqual(
            summary["evidenceSource"]["collectedAt"],
            "2026-09-14T02:41:00+00:00",
        )
        self.assertEqual(
            summary["evidenceSource"]["retrievedAt"],
            ["2026-09-14T02:40:41+00:00"] * 2,
        )
        self.assertEqual(
            {path: path.read_bytes() for path in source_before}, source_before
        )

    def test_source_hash_drift_is_rejected_before_output(self) -> None:
        summary_path = self.evidence_dir / review.SUMMARY_NAME
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        summary["source"]["sha256"] = "0" * 64
        summary_path.write_text(json.dumps(summary), encoding="utf-8")

        with self.assertRaisesRegex(review.RegionAuditError, "SHA-256"):
            self.run_review()
        self.assert_no_output()

    def test_normalized_uuid_duplicate_is_rejected(self) -> None:
        duplicate = deepcopy(self.evidence_rows[0])
        duplicate["storeId"] = UUID_A.upper()
        duplicate["candidateId"] = "candidate-duplicate"
        self.evidence_rows.append(duplicate)
        self.write_inputs()

        with self.assertRaisesRegex(review.RegionAuditError, "정규화 후 중복"):
            self.run_review()
        self.assert_no_output()

    def test_swapped_uuid_candidate_binding_is_rejected(self) -> None:
        self.evidence_rows[0]["candidateId"] = "candidate-b"
        self.evidence_rows[1]["candidateId"] = "candidate-a"
        self.write_inputs()

        with self.assertRaisesRegex(review.RegionAuditError, "연결이 바뀌"):
            self.run_review()
        self.assert_no_output()

    def test_missing_and_orphan_evidence_are_rejected(self) -> None:
        for mode in ("missing", "orphan"):
            with self.subTest(mode=mode):
                original = deepcopy(self.evidence_rows)
                if mode == "missing":
                    self.evidence_rows = self.evidence_rows[:1]
                else:
                    self.evidence_rows[1] = self.evidence_row(
                        "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
                        "candidate-orphan",
                        "Orphan",
                        "서울 용산구 길 99",
                    )
                self.write_inputs()
                with self.assertRaisesRegex(review.RegionAuditError, "누락 또는 고아"):
                    self.run_review()
                self.assert_no_output()
                self.evidence_rows = original

    def test_name_and_query_address_drift_are_rejected(self) -> None:
        for field, value in (("name", "Changed"), ("queryAddress", "서울 용산구 길 10 1층")):
            with self.subTest(field=field):
                original = self.evidence_rows[0][field]
                self.evidence_rows[0][field] = value
                self.write_inputs()
                with self.assertRaises(review.RegionAuditError):
                    self.run_review()
                self.assert_no_output()
                self.evidence_rows[0][field] = original

    def test_invalid_legal_region_shapes_are_withheld_without_using_admin_code(
        self,
    ) -> None:
        cases = (
            ("malformed", "1117010101", "후암동", "LEGAL_REGION_CODE_INVALID"),
            ("parent", "1117000000", "후암동", "LEGAL_REGION_PARENT_CODE"),
            ("blank-name", "1117010100", "", "LEGAL_REGION_NAME_INVALID"),
        )
        for mode, code, name, expected_reason in cases:
            with self.subTest(mode=mode):
                candidate = self.evidence_rows[0]["candidates"][0]
                candidate["b_code"] = code
                candidate["region_3depth_name"] = name
                self.write_inputs()
                _, package = self.run_review()
                excluded = next(
                    row for row in package["excluded"] if row["storeId"] == UUID_A
                )
                self.assertIn(expected_reason, excluded["reasonCodes"])
                self.assertNotIn("proposedUpdate", excluded)
                self.output = self.root / f"output-{mode}"
                self.evidence_rows[0] = self.evidence_row(
                    UUID_A,
                    "candidate-a",
                    "Alpha Burger",
                    "서울 용산구 길 10",
                )

    def test_boolean_counts_and_duplicate_json_keys_are_rejected(self) -> None:
        evidence_path = self.evidence_dir / review.EVIDENCE_NAME
        for mode in ("boolean-count", "duplicate-key"):
            with self.subTest(mode=mode):
                self.write_inputs()
                if mode == "boolean-count":
                    row = deepcopy(self.evidence_rows[0])
                    row["totalCount"] = True
                    lines = evidence_path.read_text(encoding="utf-8").splitlines()
                    lines[0] = json.dumps(row, ensure_ascii=False)
                    evidence_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
                else:
                    lines = evidence_path.read_text(encoding="utf-8").splitlines()
                    lines[0] = lines[0][:-1] + ', "status": "duplicate"}'
                    evidence_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
                with self.assertRaises(review.RegionAuditError):
                    self.run_review()
                self.assert_no_output()

    def test_empty_or_duplicate_csv_headers_and_existing_output_are_rejected(
        self,
    ) -> None:
        with self.publish.open("w", encoding="utf-8", newline="") as stream:
            csv.writer(stream).writerow(HEADERS + [""])
        with self.assertRaises(review.RegionAuditError):
            self.run_review()
        self.assert_no_output()

        self.write_inputs()
        with self.publish.open("w", encoding="utf-8", newline="") as stream:
            csv.writer(stream).writerow(HEADERS + ["candidateId"])
        with self.assertRaises(review.RegionAuditError):
            self.run_review()
        self.assert_no_output()

        self.write_inputs()
        self.output.mkdir()
        sentinel = self.output / "reviewer-note.txt"
        sentinel.write_text("preserve", encoding="utf-8")
        with self.assertRaisesRegex(review.RegionAuditError, "이미 존재"):
            self.run_review()
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve")

    def test_proposal_cannot_mutate_identity_style_status_coordinates_or_dates(
        self,
    ) -> None:
        _, package = self.run_review()
        forbidden = {
            "id",
            "candidateId",
            "name",
            "address",
            "burger_style",
            "verification_status",
            "is_active",
            "latitude",
            "longitude",
            "verified_at",
            "updated_at",
        }
        for row in package["reviewCandidates"]:
            self.assertEqual(set(row["proposedUpdate"]), {"region"})
            self.assertTrue(forbidden.isdisjoint(row["proposedUpdate"]))
        for row in package["excluded"]:
            self.assertNotIn("proposedUpdate", row)


if __name__ == "__main__":
    unittest.main()
