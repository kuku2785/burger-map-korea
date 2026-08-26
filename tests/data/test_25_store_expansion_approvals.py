from __future__ import annotations

import csv
import datetime as dt
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = PROJECT_ROOT / "scripts" / "data"
FIXTURE_PATH = (
    PROJECT_ROOT / "tests" / "fixtures" / "virtual_25_store_expansion_approvals.json"
)
MIGRATION_PATH = PROJECT_ROOT / "supabase" / "migrations" / "0001_init_store_schema.sql"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


approval_tool = load_module(
    "apply_25_store_expansion_approvals_test",
    SCRIPT_DIR / "apply_25_store_expansion_approvals.py",
)
sql_tool = load_module(
    "generate_25_store_expansion_sql_test",
    SCRIPT_DIR / "generate_25_store_expansion_sql.py",
)
from store_publishing_common import REVIEW_HEADERS, StorePublishingError  # noqa: E402


class TwentyFiveStoreExpansionApprovalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_directory.name)
        self.publish_path = self.root / "publish.csv"
        self.expansion_path = self.root / "expansion.csv"
        self.style_path = self.root / "styles.csv"
        self.staging_path = self.root / "staging.csv"
        self.hold_path = self.root / "hold.csv"
        self.kakao_path = self.root / "kakao.csv"
        self.approval_path = self.root / "approvals.json"
        self.sql_path = self.root / "phase6b.sql"
        self.approval_path.write_text(
            FIXTURE_PATH.read_text(encoding="utf-8"), encoding="utf-8"
        )
        self.fixture = json.loads(self.approval_path.read_text(encoding="utf-8"))
        self.approvals = self.fixture["approvals"]
        self.approval_by_candidate = {
            item["candidateId"]: item for item in self.approvals
        }
        self.generated_hold_uuid = uuid.UUID("20000000-0000-4000-8000-000000000001")
        self._write_inputs()

    def tearDown(self) -> None:
        self.temp_directory.cleanup()

    @staticmethod
    def _write_csv(path: Path, headers, rows) -> None:
        with path.open("w", encoding="utf-8-sig", newline="") as output_file:
            writer = csv.DictWriter(output_file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)

    @staticmethod
    def _read_csv(path: Path):
        with path.open("r", encoding="utf-8-sig", newline="") as input_file:
            reader = csv.DictReader(input_file)
            return list(reader.fieldnames or []), list(reader)

    @staticmethod
    def _sha(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _write_inputs(self) -> None:
        self.publish_rows = []
        self.expansion_rows = []
        self.style_rows = []
        self.staging_rows = []
        self.hold_rows = []
        self.kakao_rows = []

        existing_styles = ["classic"] * 7 + ["other"] * 2 + ["chicken"]
        for index, style in enumerate(existing_styles, start=1):
            candidate_id = f"virtual_public_{index:02d}"
            store_id = f"30000000-0000-4000-8000-{index:012d}"
            name = f"Existing Public Burger {index:02d}"
            address = f"Existing Road {index:02d}"
            latitude = f"37.{600 + index}"
            longitude = f"126.{950 + index}"
            self.publish_rows.append(
                {
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                    "burgerStyle": style,
                    "sourceType": "mixed",
                    "sourceAsOf": "2026-06-30",
                    "publishDecision": "verified",
                    "isActive": "true",
                    "verifiedAt": "2026-08-18T12:00:00+09:00",
                    "verificationNote": "Existing public approval.",
                }
            )
            self.style_rows.append(
                {
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "proposedBurgerStyle": style,
                    "reviewStatus": "approved",
                }
            )

        for index in range(1, 15):
            candidate_id = f"virtual_pending_{index:02d}"
            store_id = f"10000000-0000-4000-8000-{index:012d}"
            approval = self.approval_by_candidate.get(candidate_id)
            name = approval["name"] if approval else f"Unapproved Burger {index:02d}"
            address = approval["address"] if approval else f"Unapproved Road {index:02d}"
            latitude = approval["latitude"] if approval else f"37.{530 + index}"
            longitude = approval["longitude"] if approval else f"126.{930 + index}"
            style = approval["approvedStyle"] if approval else "unclassified"
            self.publish_rows.append(
                {
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                    "burgerStyle": "",
                    "sourceType": "mixed",
                    "sourceAsOf": "",
                    "publishDecision": "pending",
                    "isActive": "false",
                    "verifiedAt": "",
                    "verificationNote": "",
                }
            )
            self.style_rows.append(
                {
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "proposedBurgerStyle": style,
                    "reviewStatus": "approved" if approval else "needs_recheck",
                }
            )
            self.staging_rows.append(
                {
                    "candidateId": candidate_id,
                    "displayName": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                }
            )
            phase = {header: "" for header in approval_tool.OUTPUT_HEADERS}
            phase.update(
                {
                    "reviewItemId": approval["reviewItemId"] if approval else f"p6b_unapproved_{index}",
                    "sourceGroup": "pending",
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "discoveryId": "",
                    "sourcePlaceId": approval["sourcePlaceId"] if approval else f"pending_place_{index}",
                    "name": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                    "currentPublishDecision": "pending",
                    "currentIsActive": "false",
                    "currentBurgerStyle": style,
                    "latestEvidenceAsOf": "2026-08-20",
                    "recommendedDecision": "ready_for_user_approval" if approval else "needs_manual_check",
                }
            )
            self.expansion_rows.append(phase)

        for index in range(1, 5):
            candidate_id = f"virtual_hold_{index:02d}"
            approval = self.approval_by_candidate.get(candidate_id)
            name = approval["name"] if approval else f"Unresolved Hold {index:02d}"
            address = approval["address"] if approval else f"Hold Road {index:02d}"
            latitude = approval["latitude"] if approval else f"37.{520 + index}"
            longitude = approval["longitude"] if approval else f"126.{920 + index}"
            place_id = approval["sourcePlaceId"] if approval else f"hold_place_{index:02d}"
            discovery_id = approval["discoveryId"] if approval else f"virtual_discovery_{index:02d}"
            self.hold_rows.append(
                {
                    "candidateId": candidate_id,
                    "sourcePlaceId": place_id,
                    "name": name,
                    "previousStatus": "needs_recheck",
                    "stagingStatus": "hold_needs_recheck",
                    "holdReason": "Synthetic hold reason.",
                }
            )
            self.kakao_rows.append(
                {
                    "discoveryId": discovery_id,
                    "sourcePlaceId": place_id,
                    "name": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                }
            )
            phase = {header: "" for header in approval_tool.OUTPUT_HEADERS}
            phase.update(
                {
                    "reviewItemId": approval["reviewItemId"] if approval else f"p6b_hold_{index}",
                    "sourceGroup": "hold",
                    "candidateId": candidate_id,
                    "discoveryId": discovery_id,
                    "sourcePlaceId": place_id,
                    "name": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                    "currentPublishDecision": "needs_recheck",
                    "currentIsActive": "false",
                    "currentBurgerStyle": "unclassified",
                    "latestEvidenceAsOf": "2026-08-20",
                    "recommendedDecision": "hold_resolved_ready_for_user_approval" if approval else "hold_still_needs_manual_check",
                }
            )
            self.expansion_rows.append(phase)

        self._write_csv(self.publish_path, REVIEW_HEADERS, self.publish_rows)
        self._write_csv(self.expansion_path, approval_tool.OUTPUT_HEADERS, self.expansion_rows)
        self._write_csv(
            self.style_path,
            [
                "storeId",
                "candidateId",
                "name",
                "address",
                "proposedBurgerStyle",
                "reviewStatus",
            ],
            self.style_rows,
        )
        self._write_csv(
            self.staging_path,
            ["candidateId", "displayName", "address", "latitude", "longitude"],
            self.staging_rows,
        )
        self._write_csv(
            self.hold_path,
            ["candidateId", "sourcePlaceId", "name", "previousStatus", "stagingStatus", "holdReason"],
            self.hold_rows,
        )
        self._write_csv(
            self.kakao_path,
            ["discoveryId", "sourcePlaceId", "name", "address", "latitude", "longitude"],
            self.kakao_rows,
        )

    def _apply(self, *, now: dt.datetime | None = None):
        return approval_tool.apply_25_store_expansion_approvals(
            self.publish_path,
            self.expansion_path,
            self.style_path,
            self.staging_path,
            self.hold_path,
            self.kakao_path,
            self.approval_path,
            now=now
            or dt.datetime(
                2026,
                8,
                25,
                16,
                30,
                tzinfo=dt.timezone(dt.timedelta(hours=9)),
            ),
            uuid_factory=lambda: self.generated_hold_uuid,
        )

    def test_applies_only_thirteen_and_preserves_other_rows_and_inputs(self) -> None:
        protected = (
            self.expansion_path,
            self.style_path,
            self.staging_path,
            self.hold_path,
            self.kakao_path,
        )
        hashes = {path: self._sha(path) for path in protected}
        unapproved = {
            row["candidateId"]: dict(row)
            for row in self.publish_rows
            if row["candidateId"] not in self.approval_by_candidate
        }

        rows = self._apply()

        self.assertEqual(len(rows), 25)
        self.assertEqual(sum(row["publishDecision"] == "verified" for row in rows), 23)
        self.assertEqual(sum(row["publishDecision"] == "pending" for row in rows), 2)
        self.assertEqual(sum(row["isActive"] == "true" for row in rows), 23)
        by_candidate = {row["candidateId"]: row for row in rows}
        for candidate_id, original in unapproved.items():
            self.assertEqual(by_candidate[candidate_id], original)
        self.assertEqual(hashes, {path: self._sha(path) for path in protected})

    def test_hold_uuid_and_verified_at_are_preserved_on_rerun(self) -> None:
        first_rows = self._apply()
        first_hash = self._sha(self.publish_path)
        hold = next(row for row in first_rows if row["candidateId"] == "virtual_hold_01")
        self.assertEqual(hold["storeId"], str(self.generated_hold_uuid))
        self.assertEqual(hold["verifiedAt"], "2026-08-25T16:30:00+09:00")

        second_rows = self._apply()

        self.assertEqual(self._sha(self.publish_path), first_hash)
        self.assertEqual(second_rows, first_rows)

    def test_rejects_naive_now_before_initial_apply_and_verified_rerun(self) -> None:
        naive = dt.datetime(2026, 8, 25, 16, 30)
        initial_hash = self._sha(self.publish_path)
        with self.assertRaisesRegex(StorePublishingError, "시간대"):
            self._apply(now=naive)
        self.assertEqual(self._sha(self.publish_path), initial_hash)

        self._apply()
        applied_hash = self._sha(self.publish_path)
        with self.assertRaisesRegex(StorePublishingError, "시간대"):
            self._apply(now=naive)
        self.assertEqual(self._sha(self.publish_path), applied_hash)

    def test_accepts_timezone_aware_utc_and_converts_verified_at_to_kst(self) -> None:
        rows = self._apply(
            now=dt.datetime(2026, 8, 25, 7, 30, tzinfo=dt.timezone.utc)
        )

        approved = [
            row
            for row in rows
            if row["candidateId"] in self.approval_by_candidate
        ]
        self.assertEqual(len(approved), 13)
        self.assertEqual(
            {row["verifiedAt"] for row in approved},
            {"2026-08-25T16:30:00+09:00"},
        )

    def test_unclassified_and_previous_exclusion_withdrawal_are_recorded(self) -> None:
        rows = self._apply()
        by_candidate = {row["candidateId"]: row for row in rows}
        branch = by_candidate["virtual_pending_12"]
        main = by_candidate["virtual_pending_06"]
        self.assertEqual((branch["burgerStyle"], main["burgerStyle"]), ("unclassified", "unclassified"))
        self.assertIn("이전 제외 결정을", branch["verificationNote"])
        self.assertNotEqual(branch["storeId"], main["storeId"])

    def test_stable_id_name_address_store_and_candidate_mismatches_fail_atomically(self) -> None:
        mutations = (
            lambda item: item.update(reviewItemId="p6b_missing"),
            lambda item: item.update(name="Wrong Name"),
            lambda item: item.update(address="Wrong Road"),
            lambda item: item.update(storeId="90000000-0000-4000-8000-000000000001"),
            lambda item: item.update(candidateId="wrong_candidate"),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.temp_directory.cleanup()
                self.setUp()
                payload = json.loads(self.approval_path.read_text(encoding="utf-8"))
                mutation(payload["approvals"][0])
                self.approval_path.write_text(json.dumps(payload), encoding="utf-8")
                before = self._sha(self.publish_path)
                with self.assertRaises(StorePublishingError):
                    self._apply()
                self.assertEqual(self._sha(self.publish_path), before)

    def test_duplicate_stable_id_and_partial_application_are_blocked(self) -> None:
        payload = json.loads(self.approval_path.read_text(encoding="utf-8"))
        payload["approvals"][1]["reviewItemId"] = payload["approvals"][0]["reviewItemId"]
        self.approval_path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaises(StorePublishingError):
            self._apply()

        self.temp_directory.cleanup()
        self.setUp()
        self.publish_rows[10].update(
            {
                "burgerStyle": "other",
                "sourceAsOf": "2026-08-20",
                "publishDecision": "verified",
                "isActive": "true",
                "verifiedAt": "2026-08-25T15:00:00+09:00",
                "verificationNote": "partial",
            }
        )
        self._write_csv(self.publish_path, REVIEW_HEADERS, self.publish_rows)
        with self.assertRaises(StorePublishingError):
            self._apply()

    def test_generates_exact_thirteen_row_guarded_sql(self) -> None:
        rows = self._apply()
        existing_ids = {
            row["storeId"] for row in rows if row["candidateId"].startswith("virtual_public")
        }

        count = sql_tool.generate_25_store_expansion_sql(
            self.publish_path,
            self.expansion_path,
            self.style_path,
            self.approval_path,
            MIGRATION_PATH,
            self.sql_path,
        )
        sql = self.sql_path.read_text(encoding="utf-8")

        self.assertEqual(count, 13)
        self.assertIn("total_count <> 10", sql)
        self.assertIn("public_count <> 10", sql)
        self.assertIn("existing_new_count <> 0", sql)
        self.assertIn("inserted_count <> 13", sql)
        self.assertIn("total_count <> 23", sql)
        self.assertIn("public_count <> 23", sql)
        self.assertIn("matched_count <> 13", sql)
        self.assertIn("matched_style_count <> 5", sql)
        self.assertEqual(sql.count("TIMESTAMPTZ "), 13)
        for store_id in existing_ids:
            self.assertNotIn(store_id, sql)
        self.assertNotRegex(sql.lower(), r"\b(update|delete|upsert|rpc)\b|on\s+conflict")
        for approval in self.approvals:
            self.assertNotIn(approval["candidateId"], sql)
            self.assertNotIn(approval["reviewItemId"], sql)

    def test_sql_rerun_is_identical_and_changed_existing_output_is_blocked(self) -> None:
        self._apply()
        sql_tool.generate_25_store_expansion_sql(
            self.publish_path,
            self.expansion_path,
            self.style_path,
            self.approval_path,
            MIGRATION_PATH,
            self.sql_path,
        )
        first_hash = self._sha(self.sql_path)
        sql_tool.generate_25_store_expansion_sql(
            self.publish_path,
            self.expansion_path,
            self.style_path,
            self.approval_path,
            MIGRATION_PATH,
            self.sql_path,
        )
        self.assertEqual(self._sha(self.sql_path), first_hash)

        self.sql_path.write_text("changed", encoding="utf-8")
        with self.assertRaises(StorePublishingError):
            sql_tool.generate_25_store_expansion_sql(
                self.publish_path,
                self.expansion_path,
                self.style_path,
                self.approval_path,
                MIGRATION_PATH,
                self.sql_path,
            )


if __name__ == "__main__":
    unittest.main()
