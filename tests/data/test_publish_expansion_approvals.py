from __future__ import annotations

import csv
import datetime as dt
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = PROJECT_ROOT / "scripts" / "data"
FIXTURE_PATH = (
    PROJECT_ROOT / "tests" / "fixtures" / "virtual_publish_expansion_approvals.json"
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
    "apply_publish_expansion_approvals_test",
    SCRIPT_DIR / "apply_publish_expansion_approvals.py",
)
sql_tool = load_module(
    "generate_publish_expansion_sql_test",
    SCRIPT_DIR / "generate_publish_expansion_sql.py",
)
from store_publishing_common import REVIEW_HEADERS, StorePublishingError  # noqa: E402


class PublishExpansionApprovalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_directory.name)
        self.publish_path = self.root / "publish.csv"
        self.expansion_path = self.root / "expansion.csv"
        self.style_path = self.root / "styles.csv"
        self.staging_path = self.root / "staging.csv"
        self.hold_path = self.root / "hold.csv"
        self.approval_path = self.root / "approvals.json"
        self.output_sql_path = self.root / "expansion.sql"
        self.approval_path.write_text(
            FIXTURE_PATH.read_text(encoding="utf-8"), encoding="utf-8"
        )
        self.fixture = json.loads(self.approval_path.read_text(encoding="utf-8"))
        self.styles = {
            item["candidateId"]: item["approvedStyle"]
            for item in self.fixture["approvals"]
        }
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
    def _sha256(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _write_inputs(self) -> None:
        self.publish_rows = []
        self.expansion_rows = []
        self.style_rows = []
        self.staging_rows = []
        for index in range(1, 24):
            candidate_id = f"virtual_pending_{index:03d}"
            store_id = f"00000000-0000-4000-8000-{index:012d}"
            name = (
                "Virtual Denied Burger"
                if index == 21
                else f"Virtual Burger {index}"
            )
            if index == 1:
                name = "Virtual O'Burger 1"
                self.fixture["approvals"][0]["name"] = name
                self.approval_path.write_text(
                    json.dumps(self.fixture, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
            address = f"Virtual Road {index}"
            latitude = f"37.{500000 + index}"
            longitude = f"126.{900000 + index}"
            style = self.styles.get(candidate_id, "unclassified")
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
            expansion = {header: "" for header in approval_tool.OUTPUT_HEADERS}
            expansion.update(
                {
                    "reviewNumber": str(index),
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "latitude": latitude,
                    "longitude": longitude,
                    "currentPublishDecision": "pending",
                    "currentIsActive": "false",
                    "currentBurgerStyle": style,
                    "recommendedDecision": (
                        "ready_for_user_approval"
                        if index <= 9
                        else "needs_manual_check"
                    ),
                }
            )
            self.expansion_rows.append(expansion)
            self.style_rows.append(
                {
                    "storeId": store_id,
                    "candidateId": candidate_id,
                    "name": name,
                    "address": address,
                    "proposedBurgerStyle": style,
                    "reviewStatus": "approved" if index <= 9 else "needs_recheck",
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

        self.public_store_id = "00000000-0000-4000-8000-000000000100"
        self.publish_rows.append(
            {
                "storeId": self.public_store_id,
                "candidateId": "virtual_public_100",
                "name": "Existing Public Burger",
                "address": "Existing Road 100",
                "latitude": "37.6",
                "longitude": "126.99",
                "burgerStyle": "classic",
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
                "storeId": self.public_store_id,
                "candidateId": "virtual_public_100",
                "name": "Existing Public Burger",
                "address": "Existing Road 100",
                "proposedBurgerStyle": "classic",
                "reviewStatus": "approved",
            }
        )
        self.staging_rows.append(
            {
                "candidateId": "virtual_public_100",
                "displayName": "Existing Public Burger",
                "address": "Existing Road 100",
                "latitude": "37.6",
                "longitude": "126.99",
            }
        )
        self.hold_rows = [
            {
                "candidateId": f"virtual_hold_{index:03d}",
                "name": f"Virtual Hold {index}",
                "stagingStatus": "hold_needs_recheck",
            }
            for index in range(1, 5)
        ]
        self._write_csv(self.publish_path, approval_tool.REVIEW_HEADERS, self.publish_rows)
        self._write_csv(
            self.expansion_path, approval_tool.OUTPUT_HEADERS, self.expansion_rows
        )
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
            ["candidateId", "name", "stagingStatus"],
            self.hold_rows,
        )

    def _apply(self):
        return approval_tool.apply_publish_expansion_approvals(
            self.publish_path,
            self.expansion_path,
            self.style_path,
            self.staging_path,
            self.hold_path,
            self.approval_path,
            now=dt.datetime(2026, 8, 24, 15, 30, tzinfo=dt.timezone(dt.timedelta(hours=9))),
        )

    def test_applies_exact_nine_and_preserves_unapproved_rows_and_inputs(self) -> None:
        protected = (self.expansion_path, self.style_path, self.staging_path, self.hold_path)
        hashes_before = {path: self._sha256(path) for path in protected}
        unapproved_before = {
            row["candidateId"]: dict(row)
            for row in self.publish_rows
            if row["candidateId"] not in self.styles
        }

        rows = self._apply()

        self.assertEqual(len(rows), 24)
        self.assertEqual(sum(row["publishDecision"] == "verified" for row in rows), 10)
        self.assertEqual(sum(row["publishDecision"] == "pending" for row in rows), 14)
        self.assertEqual(sum(row["isActive"] == "true" for row in rows), 10)
        by_candidate = {row["candidateId"]: row for row in rows}
        for approval in self.fixture["approvals"]:
            row = by_candidate[approval["candidateId"]]
            self.assertEqual(row["burgerStyle"], approval["approvedStyle"])
            self.assertEqual(row["sourceAsOf"], approval["sourceAsOf"])
            self.assertEqual(row["verifiedAt"], "2026-08-24T15:30:00+09:00")
        for candidate_id, original in unapproved_before.items():
            self.assertEqual(by_candidate[candidate_id], original)
        denied = by_candidate["virtual_pending_021"]
        self.assertEqual((denied["publishDecision"], denied["isActive"]), ("pending", "false"))
        self.assertEqual(hashes_before, {path: self._sha256(path) for path in protected})

    def test_rerun_is_identical_and_preserves_verified_at(self) -> None:
        self._apply()
        first_hash = self._sha256(self.publish_path)
        first_rows = self._read_csv(self.publish_path)[1]

        second_rows = self._apply()

        self.assertEqual(self._sha256(self.publish_path), first_hash)
        self.assertEqual(second_rows, first_rows)

    def test_wrong_name_number_or_id_fails_without_partial_write(self) -> None:
        mutations = (
            lambda: self.fixture["approvals"][0].update(name="Wrong Name"),
            lambda: self.fixture["approvals"][0].update(reviewNumber=10),
            lambda: self.fixture["approvals"][0].update(candidateId="wrong_candidate"),
            lambda: self.fixture["approvals"][0].update(
                storeId="10000000-0000-4000-8000-000000000001"
            ),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.temp_directory.cleanup()
                self.setUp()
                before = self._sha256(self.publish_path)
                mutation()
                self.approval_path.write_text(
                    json.dumps(self.fixture, ensure_ascii=False), encoding="utf-8"
                )
                with self.assertRaises(StorePublishingError):
                    self._apply()
                self.assertEqual(self._sha256(self.publish_path), before)

    def test_denylist_overlap_style_mismatch_and_future_date_are_blocked(self) -> None:
        cases = []
        denied_approval = dict(self.fixture["approvals"][0])
        denied_approval.update(self.fixture["denied"][0])
        cases.append(lambda payload: payload["approvals"].__setitem__(0, denied_approval))
        cases.append(lambda payload: payload["approvals"][0].update(approvedStyle="smash"))
        cases.append(lambda payload: payload["approvals"][0].update(sourceAsOf="2026-08-25"))
        for mutation in cases:
            with self.subTest(mutation=mutation):
                self.temp_directory.cleanup()
                self.setUp()
                payload = json.loads(self.approval_path.read_text(encoding="utf-8"))
                mutation(payload)
                self.approval_path.write_text(
                    json.dumps(payload, ensure_ascii=False), encoding="utf-8"
                )
                before = self._sha256(self.publish_path)
                with self.assertRaises(StorePublishingError):
                    self._apply()
                self.assertEqual(self._sha256(self.publish_path), before)

    def test_partial_prior_application_is_blocked(self) -> None:
        self.publish_rows[0].update(
            {
                "burgerStyle": "classic",
                "sourceAsOf": "2026-08-01",
                "publishDecision": "verified",
                "isActive": "true",
                "verifiedAt": "2026-08-24T15:00:00+09:00",
                "verificationNote": self.fixture["approvals"][0]["verificationNote"],
            }
        )
        self._write_csv(self.publish_path, REVIEW_HEADERS, self.publish_rows)
        before = self._sha256(self.publish_path)

        with self.assertRaises(StorePublishingError):
            self._apply()

        self.assertEqual(self._sha256(self.publish_path), before)

    def test_generates_guarded_insert_for_only_the_nine_approved_rows(self) -> None:
        self._apply()

        count = sql_tool.generate_publish_expansion_sql(
            self.publish_path,
            self.approval_path,
            MIGRATION_PATH,
            self.output_sql_path,
        )
        sql = self.output_sql_path.read_text(encoding="utf-8")

        self.assertEqual(count, 9)
        self.assertIn("begin;", sql.lower())
        self.assertIn("commit;", sql.lower())
        self.assertIn("existing_count <> 0", sql)
        self.assertIn("get diagnostics inserted_count = row_count", sql.lower())
        self.assertIn("inserted_count <> 9", sql)
        self.assertIn("valid_count <> 9", sql)
        self.assertIn("O''Burger", sql)
        self.assertNotIn(self.public_store_id, sql)
        self.assertNotIn("00000000-0000-4000-8000-000000000021", sql)
        self.assertNotRegex(sql.lower(), r"\b(update|delete|upsert|rpc)\b|on\s+conflict")
        for candidate_id in [
            row["candidateId"] for row in self.fixture["approvals"]
        ]:
            self.assertNotIn(candidate_id, sql)
        self.assertEqual(sql.count("TIMESTAMPTZ "), 9)

    def test_sql_generation_rejects_existing_output_and_changed_approval(self) -> None:
        self._apply()
        sql_tool.generate_publish_expansion_sql(
            self.publish_path,
            self.approval_path,
            MIGRATION_PATH,
            self.output_sql_path,
        )
        with self.assertRaises(StorePublishingError):
            sql_tool.generate_publish_expansion_sql(
                self.publish_path,
                self.approval_path,
                MIGRATION_PATH,
                self.output_sql_path,
            )

        self.output_sql_path.unlink()
        rows = self._read_csv(self.publish_path)[1]
        rows[0]["burgerStyle"] = "smash"
        self._write_csv(self.publish_path, REVIEW_HEADERS, rows)
        with self.assertRaises(StorePublishingError):
            sql_tool.generate_publish_expansion_sql(
                self.publish_path,
                self.approval_path,
                MIGRATION_PATH,
                self.output_sql_path,
            )


if __name__ == "__main__":
    unittest.main()
