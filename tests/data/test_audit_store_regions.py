from __future__ import annotations

import csv
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = PROJECT_ROOT / "scripts" / "data"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import audit_store_regions as audit  # noqa: E402


UUID_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
UUID_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
UUID_C = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

PUBLISH_HEADERS = [
    "storeId",
    "candidateId",
    "name",
    "address",
    "burgerStyle",
    "sourceAsOf",
    "publishDecision",
    "isActive",
]
STAGING_HEADERS = ["candidateId", "sourceStoreId"]
LOCAL_HEADERS = ["id", "name", "address", "burger_style"]
RAW_HEADERS = [
    "상가업소번호",
    "상호명",
    "시도코드",
    "시도명",
    "시군구코드",
    "시군구명",
    "행정동코드",
    "행정동명",
    "법정동코드",
    "법정동명",
    "도로명주소",
]


def write_csv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as destination:
        writer = csv.DictWriter(destination, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def write_positional_csv(path: Path, headers: list[str], rows: list[list[str]]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as destination:
        writer = csv.writer(destination)
        writer.writerow(headers)
        writer.writerows(rows)


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class AuditStoreRegionsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.publish_path = self.root / "publish.csv"
        self.staging_path = self.root / "staging.csv"
        self.raw_path = self.root / "raw.csv"
        self.local_path = self.root / "local.csv"
        self.asset_path = self.root / "asset.json"
        self.publish_headers = list(PUBLISH_HEADERS)
        self.staging_headers = list(STAGING_HEADERS)
        self.local_headers = list(LOCAL_HEADERS)
        self.publish_rows = [self.publish_row()]
        self.staging_rows = [{"candidateId": "candidate-a", "sourceStoreId": "raw-a"}]
        self.raw_rows = [self.raw_row()]
        self.local_rows = [
            {
                "id": UUID_A,
                "name": "Approved Burger",
                "address": "서울 용산구 한강대로 1",
                "burger_style": "classic",
            }
        ]
        self.asset_items: list[dict[str, object]] = [{"id": "candidate-a"}]
        self.write_inputs()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def publish_row(
        self,
        *,
        store_id: str = UUID_A,
        candidate_id: str = "candidate-a",
        name: str = "Approved Burger",
        address: str = "서울 용산구 한강대로 1",
        style: str = "classic",
        source_as_of: str = "2026-08-25",
        decision: str = "verified",
        active: str = "true",
    ) -> dict[str, str]:
        return {
            "storeId": store_id,
            "candidateId": candidate_id,
            "name": name,
            "address": address,
            "burgerStyle": style,
            "sourceAsOf": source_as_of,
            "publishDecision": decision,
            "isActive": active,
        }

    def raw_row(
        self,
        *,
        source_id: str = "raw-a",
        name: str = "Source Ledger Name",
        address: str = "서울 용산구 한강대로 1",
    ) -> dict[str, str]:
        return {
            "상가업소번호": source_id,
            "상호명": name,
            "시도코드": "11",
            "시도명": "서울특별시",
            "시군구코드": "11170",
            "시군구명": "용산구",
            "행정동코드": "11170530",
            "행정동명": "남영동",
            "법정동코드": "1117010100",
            "법정동명": "후암동",
            "도로명주소": address,
        }

    def write_inputs(self) -> None:
        write_csv(self.publish_path, self.publish_headers, self.publish_rows)
        write_csv(self.staging_path, self.staging_headers, self.staging_rows)
        write_csv(self.raw_path, RAW_HEADERS, self.raw_rows)
        write_csv(self.local_path, self.local_headers, self.local_rows)
        self.asset_path.write_text(
            json.dumps(self.asset_items, ensure_ascii=False), encoding="utf-8"
        )

    def run_audit(self, output_name: str = "output") -> tuple[dict[str, object], Path]:
        output_path = self.root / output_name
        summary = audit.run_audit(
            self.publish_path,
            self.staging_path,
            self.raw_path,
            self.local_path,
            self.asset_path,
            output_path,
        )
        return summary, output_path

    def read_audit_rows(self, output_path: Path) -> list[dict[str, str]]:
        with (output_path / "region_audit.csv").open(
            "r", encoding="utf-8-sig", newline=""
        ) as source:
            return list(csv.DictReader(source))

    def test_exact_ids_link_region_fields_as_review_only_evidence(self) -> None:
        summary, output_path = self.run_audit()

        rows = self.read_audit_rows(output_path)
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["storeId"], UUID_A)
        self.assertEqual(row["candidateId"], "candidate-a")
        self.assertEqual(row["sourceStoreId"], "raw-a")
        self.assertEqual(row["sourceStoreName"], "Source Ledger Name")
        self.assertEqual(row["sourceAsOf"], "2026-08-25")
        self.assertEqual(row["administrativeDongName"], "남영동")
        self.assertEqual(row["legalDongName"], "후암동")
        self.assertEqual(row["sourceLinked"], "true")
        self.assertEqual(row["sourceAddressMatches"], "true")
        self.assertEqual(row["regionComplete"], "true")
        self.assertEqual(row["manualReviewRequired"], "true")
        self.assertEqual(row["issueCodes"], "")
        self.assertEqual(summary["counts"]["approvedTargetRows"], 1)
        self.assertEqual(summary["counts"]["sourceLinkedRows"], 1)
        self.assertFalse(summary["auditBoundary"]["remoteChecked"])
        self.assertTrue(summary["auditBoundary"]["regionDataIsSourceEvidenceOnly"])
        self.assertTrue(summary["auditBoundary"]["everyRegionRequiresReview"])

    def test_same_name_does_not_create_a_join_without_exact_ids(self) -> None:
        self.staging_rows = []
        self.raw_rows = [self.raw_row(source_id="unreferenced", name="Approved Burger")]
        self.write_inputs()

        _, output_path = self.run_audit()
        row = self.read_audit_rows(output_path)[0]

        self.assertEqual(row["sourceStoreId"], "")
        self.assertEqual(row["sourceStoreName"], "")
        self.assertEqual(row["sourceLinked"], "false")
        self.assertIn("STAGING_CANDIDATE_NOT_FOUND", row["issueCodes"])

    def test_only_verified_and_active_publish_rows_are_audited(self) -> None:
        self.publish_rows.extend(
            [
                self.publish_row(
                    store_id=UUID_B,
                    candidate_id="candidate-pending",
                    decision="pending",
                    active="false",
                ),
                self.publish_row(
                    store_id=UUID_C,
                    candidate_id="candidate-inactive",
                    decision="verified",
                    active="false",
                ),
            ]
        )
        self.write_inputs()

        summary, output_path = self.run_audit()

        self.assertEqual(
            [row["candidateId"] for row in self.read_audit_rows(output_path)],
            ["candidate-a"],
        )
        self.assertEqual(summary["counts"]["publishRows"], 3)
        self.assertEqual(summary["counts"]["approvedTargetRows"], 1)
        self.assertEqual(summary["counts"]["excludedPublishRows"], 2)

    def test_missing_source_id_stays_unlinked_and_requires_review(self) -> None:
        self.staging_rows[0]["sourceStoreId"] = ""
        self.raw_rows[0]["상호명"] = "Approved Burger"
        self.write_inputs()

        _, output_path = self.run_audit()
        row = self.read_audit_rows(output_path)[0]

        self.assertEqual(row["sourceLinked"], "false")
        self.assertEqual(row["manualReviewRequired"], "true")
        self.assertEqual(
            row["issueCodes"],
            "SOURCE_STORE_ID_MISSING|REGION_EVIDENCE_INCOMPLETE",
        )

    def test_source_id_absent_from_raw_stays_unlinked(self) -> None:
        self.staging_rows[0]["sourceStoreId"] = "missing-raw-id"
        self.raw_rows[0]["상호명"] = "Approved Burger"
        self.write_inputs()

        _, output_path = self.run_audit()
        row = self.read_audit_rows(output_path)[0]

        self.assertEqual(row["sourceStoreId"], "missing-raw-id")
        self.assertEqual(row["sourceLinked"], "false")
        self.assertEqual(row["sourceStoreName"], "")
        self.assertEqual(
            row["issueCodes"], "RAW_SOURCE_NOT_FOUND|REGION_EVIDENCE_INCOMPLETE"
        )

    def test_blank_approved_style_is_preserved_and_flagged_for_review(self) -> None:
        self.publish_rows[0]["burgerStyle"] = ""
        self.write_inputs()

        summary, output_path = self.run_audit()
        row = self.read_audit_rows(output_path)[0]

        self.assertEqual(row["burgerStyle"], "")
        self.assertIn("APPROVED_BURGER_STYLE_EMPTY", row["issueCodes"])
        differences = summary["localSnapshotComparison"]["fieldDifferences"]
        self.assertEqual(differences[0]["storeId"], UUID_A)
        self.assertEqual(
            differences[0]["fields"]["burgerStyle"],
            {"approved": "", "localSnapshot": "classic"},
        )

    def test_address_comparison_normalizes_only_whitespace_and_seoul_alias(
        self,
    ) -> None:
        self.publish_rows[0]["address"] = " 서울   용산구 한강대로 1 "
        self.raw_rows[0]["도로명주소"] = "서울특별시 용산구  한강대로 1"
        self.publish_rows.append(
            self.publish_row(
                store_id=UUID_B,
                candidate_id="candidate-b",
                address="서울 용산구 한강대로 37-2",
            )
        )
        self.staging_rows.append(
            {"candidateId": "candidate-b", "sourceStoreId": "raw-b"}
        )
        self.raw_rows.append(
            self.raw_row(source_id="raw-b", address="서울 용산구 한강대로 37 2층")
        )
        self.local_rows.append(
            {
                "id": UUID_B,
                "name": "Approved Burger",
                "address": "서울 용산구 한강대로 37-2",
                "burger_style": "classic",
            }
        )
        self.asset_items.append({"id": "candidate-b"})
        self.write_inputs()

        _, output_path = self.run_audit()
        rows = {row["candidateId"]: row for row in self.read_audit_rows(output_path)}

        self.assertEqual(rows["candidate-a"]["sourceAddressMatches"], "true")
        self.assertEqual(rows["candidate-b"]["sourceAddressMatches"], "false")
        self.assertIn("SOURCE_ADDRESS_MISMATCH", rows["candidate-b"]["issueCodes"])

    def test_publish_uuid_uniqueness_is_case_insensitive(self) -> None:
        self.publish_rows.append(
            self.publish_row(store_id=UUID_A.upper(), candidate_id="candidate-b")
        )
        self.write_inputs()

        with self.assertRaisesRegex(audit.RegionAuditError, "대소문자 구분 없이 중복"):
            self.run_audit()

    def test_duplicate_publish_candidate_fails(self) -> None:
        self.publish_rows.append(
            self.publish_row(store_id=UUID_B, candidate_id="candidate-a")
        )
        self.write_inputs()

        with self.assertRaisesRegex(audit.RegionAuditError, "candidateId가 중복"):
            self.run_audit()

    def test_duplicate_staging_candidate_fails(self) -> None:
        self.staging_rows.append(
            {"candidateId": "candidate-a", "sourceStoreId": "raw-other"}
        )
        self.write_inputs()

        with self.assertRaisesRegex(audit.RegionAuditError, "staging candidateId가 중복"):
            self.run_audit()

    def test_two_approved_candidates_cannot_share_a_staging_source_id(self) -> None:
        self.publish_rows.append(
            self.publish_row(store_id=UUID_B, candidate_id="candidate-b")
        )
        self.staging_rows.append(
            {"candidateId": "candidate-b", "sourceStoreId": "raw-a"}
        )
        self.write_inputs()

        with self.assertRaisesRegex(audit.RegionAuditError, "같은 raw 상가업소번호"):
            self.run_audit()

    def test_duplicate_referenced_raw_source_fails(self) -> None:
        self.raw_rows.append(self.raw_row(name="Duplicate Ledger Row"))
        self.write_inputs()

        with self.assertRaisesRegex(audit.RegionAuditError, "상가업소번호가 중복"):
            self.run_audit()

    def test_snapshot_and_asset_differences_are_reported_without_promotion(
        self,
    ) -> None:
        self.publish_rows.append(
            self.publish_row(store_id=UUID_B, candidate_id="candidate-b")
        )
        self.staging_rows.append(
            {"candidateId": "candidate-b", "sourceStoreId": "raw-b"}
        )
        self.raw_rows.append(self.raw_row(source_id="raw-b"))
        self.local_rows = [
            {
                "id": UUID_A,
                "name": "Local Name",
                "address": "서울 용산구 다른길 9",
                "burger_style": "chicken",
            },
            {
                "id": UUID_C,
                "name": "Local Only",
                "address": "서울 용산구 로컬길 1",
                "burger_style": "other",
            },
        ]
        self.asset_items = [{"id": "candidate-a"}, {"id": "asset-only"}]
        self.write_inputs()

        summary, output_path = self.run_audit()

        local = summary["localSnapshotComparison"]
        self.assertEqual(local["idOnlyInApprovedTarget"], [UUID_B])
        self.assertEqual(local["idOnlyInLocalSnapshot"], [UUID_C])
        self.assertEqual(local["fieldDifferences"][0]["storeId"], UUID_A)
        self.assertEqual(
            set(local["fieldDifferences"][0]["fields"]),
            {"name", "address", "burgerStyle"},
        )
        assets = summary["developmentAssetCandidateComparison"]
        self.assertEqual(assets["candidateIdOnlyInApprovedTarget"], ["candidate-b"])
        self.assertEqual(assets["candidateIdOnlyInDevelopmentAsset"], ["asset-only"])
        self.assertTrue(
            all(
                row["manualReviewRequired"] == "true"
                for row in self.read_audit_rows(output_path)
            )
        )

    def test_input_hashes_are_recorded_and_sources_are_unchanged(self) -> None:
        input_paths = {
            "publishReview": self.publish_path,
            "staging": self.staging_path,
            "rawCommercialStores": self.raw_path,
            "localSnapshot": self.local_path,
            "developmentAsset": self.asset_path,
        }
        before = {key: file_hash(path) for key, path in input_paths.items()}

        summary, _ = self.run_audit()

        after = {key: file_hash(path) for key, path in input_paths.items()}
        self.assertEqual(after, before)
        self.assertEqual(
            {key: value["sha256"] for key, value in summary["inputs"].items()},
            before,
        )

    def test_existing_output_directory_is_left_unchanged(self) -> None:
        output_path = self.root / "existing-output"
        output_path.mkdir()
        sentinel = output_path / "reviewer-note.txt"
        sentinel.write_text("preserve me", encoding="utf-8")
        before = {path.name: file_hash(path) for path in output_path.iterdir()}

        with self.assertRaisesRegex(audit.RegionAuditError, "이미 존재"):
            self.run_audit("existing-output")

        after = {path.name: file_hash(path) for path in output_path.iterdir()}
        self.assertEqual(after, before)

    def test_duplicate_and_malformed_csv_shapes_fail_safely(self) -> None:
        cases = ("duplicate_header", "short_row", "extra_value")
        for index, case in enumerate(cases):
            with self.subTest(case=case):
                if case == "duplicate_header":
                    write_csv(
                        self.publish_path,
                        self.publish_headers + ["candidateId"],
                        self.publish_rows,
                    )
                else:
                    values = [
                        self.publish_rows[0][header] for header in self.publish_headers
                    ]
                    if case == "short_row":
                        values = values[:-1]
                    else:
                        values = values + ["unexpected"]
                    write_positional_csv(
                        self.publish_path, self.publish_headers, [values]
                    )
                with self.assertRaises(audit.RegionAuditError):
                    self.run_audit(f"malformed-{index}")
                self.write_inputs()

    def test_raw_csv_row_shape_is_validated_even_when_source_is_unreferenced(
        self,
    ) -> None:
        unreferenced = self.raw_row(source_id="unused")
        values = [unreferenced[header] for header in RAW_HEADERS] + ["unexpected"]
        write_positional_csv(
            self.raw_path,
            RAW_HEADERS,
            [[self.raw_rows[0][header] for header in RAW_HEADERS], values],
        )

        with self.assertRaisesRegex(audit.RegionAuditError, "헤더보다 많은 값"):
            self.run_audit()

    def test_invalid_visibility_enum_values_are_rejected(self) -> None:
        cases = (
            ("publishDecision", ""),
            ("publishDecision", "approved"),
            ("isActive", ""),
            ("isActive", "TRUE"),
        )
        for index, (field, value) in enumerate(cases):
            with self.subTest(field=field, value=value):
                original = self.publish_rows[0][field]
                self.publish_rows[0][field] = value
                self.write_inputs()
                with self.assertRaises(audit.RegionAuditError):
                    self.run_audit(f"invalid-enum-{index}")
                self.publish_rows[0][field] = original

    def test_development_asset_ids_must_be_nonempty_unique_strings(self) -> None:
        cases: list[list[dict[str, object]]] = [
            [{}],
            [{"id": 123}],
            [{"id": " "}],
            [{"id": "candidate-a"}, {"id": " candidate-a "}],
        ]
        for index, items in enumerate(cases):
            with self.subTest(items=items):
                self.asset_path.write_text(json.dumps(items), encoding="utf-8")
                with self.assertRaises(audit.RegionAuditError):
                    self.run_audit(f"invalid-asset-{index}")

    def test_local_snapshot_verification_boundary_comes_from_actual_headers(
        self,
    ) -> None:
        summary_without_fields, _ = self.run_audit("without-verification-fields")
        self.assertFalse(
            summary_without_fields["auditBoundary"][
                "localSnapshotHasVerificationFields"
            ]
        )

        self.local_headers.extend(["verification_status", "is_active"])
        self.local_rows[0]["verification_status"] = "verified"
        self.local_rows[0]["is_active"] = "true"
        self.write_inputs()
        summary_with_fields, _ = self.run_audit("with-verification-fields")

        self.assertTrue(
            summary_with_fields["auditBoundary"]["localSnapshotHasVerificationFields"]
        )

    def test_local_snapshot_uuid_uniqueness_is_case_insensitive(self) -> None:
        duplicate = dict(self.local_rows[0])
        duplicate["id"] = UUID_A.upper()
        self.local_rows.append(duplicate)
        self.write_inputs()

        with self.assertRaisesRegex(audit.RegionAuditError, "대소문자 구분 없이 중복"):
            self.run_audit()


if __name__ == "__main__":
    unittest.main()
