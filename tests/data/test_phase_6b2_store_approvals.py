from __future__ import annotations

import csv
import datetime as dt
import hashlib
import importlib.util
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = PROJECT_ROOT / "scripts" / "data"
FIXTURE_PATH = (
    PROJECT_ROOT / "tests" / "fixtures" / "virtual_phase_6b2_store_approvals.json"
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
    "apply_phase_6b2_store_approvals_test",
    SCRIPT_DIR / "apply_phase_6b2_store_approvals.py",
)
sql_tool = load_module(
    "generate_phase_6b2_store_sql_test",
    SCRIPT_DIR / "generate_phase_6b2_store_sql.py",
)
style_correction_tool = load_module(
    "apply_phase_6b2_style_correction_test",
    SCRIPT_DIR / "apply_phase_6b2_style_correction.py",
)
style_correction_sql_tool = load_module(
    "generate_phase_6b2_style_correction_sql_test",
    SCRIPT_DIR / "generate_phase_6b2_style_correction_sql.py",
)
from store_publishing_common import REVIEW_HEADERS, StorePublishingError  # noqa: E402


class Phase6B2StoreApprovalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_directory.name)
        self.publish_path = self.root / "publish.csv"
        self.expansion_path = self.root / "expansion.csv"
        self.hold_path = self.root / "hold.csv"
        self.kakao_path = self.root / "kakao.csv"
        self.approval_path = self.root / "approvals.json"
        self.result_path = self.root / "result.json"
        self.sql_path = self.root / "phase6b2.sql"
        self.style_correction_sql_path = self.root / "phase6b2_style_correction.sql"
        self.approval_path.write_text(
            FIXTURE_PATH.read_text(encoding="utf-8"), encoding="utf-8"
        )
        self.fixture = json.loads(self.approval_path.read_text(encoding="utf-8"))
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
            return list(csv.DictReader(input_file))

    @staticmethod
    def _sha(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _publish_row(
        self,
        index: int,
        *,
        candidate_id: str,
        name: str,
        address: str,
        decision: str,
        active: str,
    ):
        return {
            "storeId": f"10000000-0000-4000-8000-{index:012d}",
            "candidateId": candidate_id,
            "name": name,
            "address": address,
            "latitude": f"37.{500 + index}",
            "longitude": f"126.{900 + index}",
            "burgerStyle": "classic" if active == "true" else "",
            "sourceType": "mixed",
            "sourceAsOf": "2026-08-20" if active == "true" else "",
            "publishDecision": decision,
            "isActive": active,
            "verifiedAt": "2026-08-20T12:00:00+09:00" if active == "true" else "",
            "verificationNote": "Existing approval" if active == "true" else "",
        }

    def _write_inputs(self) -> None:
        self.publish_rows = [
            self._publish_row(
                index,
                candidate_id=f"virtual_public_{index:02d}",
                name=f"Virtual Public {index:02d}",
                address=f"Public Road {index:02d}",
                decision="verified",
                active="true",
            )
            for index in range(1, 24)
        ]
        pending = self._publish_row(
            24,
            candidate_id="virtual_pending_24",
            name="Virtual Stacker",
            address="Virtual Road 24",
            decision="pending",
            active="false",
        )
        pending.update(latitude="37.524", longitude="126.924")
        excluded = self._publish_row(
            25,
            candidate_id="virtual_excluded_25",
            name="Virtual Manual Check",
            address="Excluded Road 25",
            decision="pending",
            active="false",
        )
        self.publish_rows.extend((pending, excluded))

        self.expansion_rows = []
        for row in self.publish_rows:
            phase = {header: "" for header in approval_tool.OUTPUT_HEADERS}
            place_id = f"place_{row['candidateId']}"
            if row["candidateId"] == "virtual_pending_24":
                place_id = "virtual_place_24"
            elif row["candidateId"] == "virtual_excluded_25":
                place_id = "virtual_place_25"
            phase.update(
                {
                    "reviewItemId": f"p6b_{row['candidateId']}",
                    "sourceGroup": "pending",
                    "storeId": row["storeId"],
                    "candidateId": row["candidateId"],
                    "sourcePlaceId": place_id,
                    "name": row["name"],
                    "address": row["address"],
                    "latitude": row["latitude"],
                    "longitude": row["longitude"],
                    "currentPublishDecision": row["publishDecision"],
                    "currentIsActive": row["isActive"],
                    "currentBurgerStyle": row["burgerStyle"] or "unclassified",
                    "latestEvidenceAsOf": "2026-08-26",
                    "recommendedDecision": "needs_manual_check",
                }
            )
            self.expansion_rows.append(phase)

        self.hold_rows = [
            {
                "candidateId": "virtual_hold_current",
                "sourcePlaceId": "virtual_place_current",
                "name": "Virtual Jack",
                "previousStatus": "needs_recheck",
                "stagingStatus": "hold_needs_recheck",
                "holdReason": "Synthetic historical address conflict",
            }
        ]
        self.kakao_rows = [
            {
                "discoveryId": "virtual_discovery_current",
                "sourcePlaceId": "virtual_place_current",
                "name": "Virtual Jack",
                "address": "Virtual Current Road",
                "latitude": "37.5301",
                "longitude": "126.9301",
                "matchedCandidateId": "",
            }
        ]
        for index in range(1, 24):
            self.kakao_rows.append(
                {
                    "discoveryId": f"virtual_discovery_{index}",
                    "sourcePlaceId": f"place_virtual_public_{index:02d}",
                    "name": f"Virtual Public {index:02d}",
                    "address": f"Public Road {index:02d}",
                    "latitude": f"37.{500 + index}",
                    "longitude": f"126.{900 + index}",
                    "matchedCandidateId": f"virtual_public_{index:02d}",
                }
            )

        self._write_csv(self.publish_path, REVIEW_HEADERS, self.publish_rows)
        self._write_csv(
            self.expansion_path, approval_tool.OUTPUT_HEADERS, self.expansion_rows
        )
        self._write_csv(
            self.hold_path,
            [
                "candidateId",
                "sourcePlaceId",
                "name",
                "previousStatus",
                "stagingStatus",
                "holdReason",
            ],
            self.hold_rows,
        )
        self._write_csv(
            self.kakao_path,
            [
                "discoveryId",
                "sourcePlaceId",
                "name",
                "address",
                "latitude",
                "longitude",
                "matchedCandidateId",
            ],
            self.kakao_rows,
        )

    def _apply(self, now=None):
        return approval_tool.apply_phase_6b2_store_approvals(
            self.publish_path,
            self.expansion_path,
            self.hold_path,
            self.kakao_path,
            self.approval_path,
            self.result_path,
            now=now
            or dt.datetime(
                2026, 8, 26, 15, 30, tzinfo=dt.timezone(dt.timedelta(hours=9))
            ),
        )

    def _set_review_style(self, candidate_id: str, style: str) -> None:
        rows = self._read_csv(self.publish_path)
        matches = [row for row in rows if row["candidateId"] == candidate_id]
        self.assertEqual(len(matches), 1)
        matches[0]["burgerStyle"] = style
        self._write_csv(self.publish_path, REVIEW_HEADERS, rows)

    def test_applies_exactly_two_and_preserves_excluded_and_inputs(self) -> None:
        protected = (
            self.expansion_path,
            self.hold_path,
            self.kakao_path,
            self.approval_path,
        )
        hashes = {path: self._sha(path) for path in protected}
        excluded_before = dict(self.publish_rows[-1])

        rows = self._apply()

        self.assertEqual(len(rows), 26)
        self.assertEqual(sum(row["publishDecision"] == "verified" for row in rows), 25)
        self.assertEqual(sum(row["isActive"] == "true" for row in rows), 25)
        self.assertEqual(sum(row["publishDecision"] == "pending" for row in rows), 1)
        by_candidate = {row["candidateId"]: row for row in rows}
        self.assertEqual(by_candidate["virtual_excluded_25"], excluded_before)
        self.assertEqual(hashes, {path: self._sha(path) for path in protected})

    def test_corrects_current_addresses_and_removes_historical_hold_address(self) -> None:
        rows = self._apply()
        by_candidate = {row["candidateId"]: row for row in rows}
        self.assertEqual(
            by_candidate["virtual_pending_24"]["address"], "Virtual Road 24 1F"
        )
        hold = by_candidate["virtual_hold_current"]
        self.assertEqual(hold["address"], "Virtual Current Road 1F")
        self.assertEqual(hold["burgerStyle"], "chicken")
        self.assertNotIn("Virtual Historical Road", json.dumps(hold))
        self.assertEqual(hold["storeId"], "20000000-0000-4000-8000-000000000001")

    def test_style_correction_changes_only_declared_burger_style(self) -> None:
        self._apply()
        self._set_review_style("virtual_hold_current", "unclassified")
        before = self._read_csv(self.publish_path)

        rows, changed = style_correction_tool.apply_phase_6b2_style_correction(
            self.publish_path,
            self.approval_path,
            today=dt.date(2026, 8, 26),
        )

        self.assertTrue(changed)
        self.assertEqual(len(rows), 26)
        after = self._read_csv(self.publish_path)
        changes = []
        for index, (old, new) in enumerate(zip(before, after, strict=True)):
            for field in REVIEW_HEADERS:
                if old[field] != new[field]:
                    changes.append((index, field, old[field], new[field]))
        self.assertEqual(
            changes,
            [(25, "burgerStyle", "unclassified", "chicken")],
        )
        self.assertEqual(
            sum(
                row["publishDecision"] == "verified" and row["isActive"] == "true"
                for row in after
            ),
            25,
        )

    def test_style_correction_is_idempotent_and_rejects_unexpected_style(self) -> None:
        self._apply()
        first_hash = self._sha(self.publish_path)
        _, changed = style_correction_tool.apply_phase_6b2_style_correction(
            self.publish_path,
            self.approval_path,
            today=dt.date(2026, 8, 26),
        )
        self.assertFalse(changed)
        self.assertEqual(self._sha(self.publish_path), first_hash)

        self._set_review_style("virtual_hold_current", "smash")
        with self.assertRaisesRegex(StorePublishingError, "neither"):
            style_correction_tool.apply_phase_6b2_style_correction(
                self.publish_path,
                self.approval_path,
                today=dt.date(2026, 8, 26),
            )

    def test_generates_one_row_guarded_style_correction_sql(self) -> None:
        self._apply()
        count = style_correction_sql_tool.generate_phase_6b2_style_correction_sql(
            self.publish_path,
            self.approval_path,
            self.style_correction_sql_path,
            today=dt.date(2026, 8, 26),
        )
        sql = self.style_correction_sql_path.read_text(encoding="utf-8")

        self.assertEqual(count, 1)
        self.assertEqual(sql.lower().count("update public.stores"), 1)
        self.assertIn("set burger_style = 'chicken'", sql)
        self.assertIn("and burger_style = 'unclassified'", sql)
        self.assertIn("name = 'Virtual Jack'", sql)
        self.assertIn("address = 'Virtual Current Road 1F'", sql)
        self.assertIn("verification_status = 'verified'", sql)
        self.assertIn("is_active = true", sql)
        self.assertEqual(sql.count("public_count <> 25"), 2)
        self.assertIn("target_count <> 1", sql)
        self.assertIn("changed_count <> 1", sql)
        self.assertNotRegex(
            sql.lower(), r"\b(insert|delete|upsert|rpc)\b|on\s+conflict"
        )
        self.assertNotIn("virtual_hold_current", sql)
        self.assertNotIn("virtual_place_current", sql)
        self.assertNotIn("https://", sql)

    def test_existing_style_correction_sql_must_be_identical(self) -> None:
        self._apply()
        arguments = (
            self.publish_path,
            self.approval_path,
            self.style_correction_sql_path,
        )
        style_correction_sql_tool.generate_phase_6b2_style_correction_sql(
            *arguments, today=dt.date(2026, 8, 26)
        )
        first_hash = self._sha(self.style_correction_sql_path)
        style_correction_sql_tool.generate_phase_6b2_style_correction_sql(
            *arguments, today=dt.date(2026, 8, 26)
        )
        self.assertEqual(self._sha(self.style_correction_sql_path), first_hash)
        self.style_correction_sql_path.write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(StorePublishingError, "will not be overwritten"):
            style_correction_sql_tool.generate_phase_6b2_style_correction_sql(
                *arguments, today=dt.date(2026, 8, 26)
            )

    def test_rerun_preserves_verified_at_uuid_and_publish_hash(self) -> None:
        first = self._apply()
        first_hash = self._sha(self.publish_path)
        second = self._apply(
            now=dt.datetime(2026, 8, 26, 9, 0, tzinfo=dt.timezone.utc)
        )
        self.assertEqual(first, second)
        self.assertEqual(self._sha(self.publish_path), first_hash)

    def test_naive_time_is_rejected_before_changes(self) -> None:
        before = self._sha(self.publish_path)
        with self.assertRaisesRegex(StorePublishingError, "시간대"):
            self._apply(now=dt.datetime(2026, 8, 26, 15, 30))
        self.assertEqual(self._sha(self.publish_path), before)

    def test_coordinate_address_reference_mismatch_is_rejected(self) -> None:
        payload = json.loads(self.approval_path.read_text(encoding="utf-8"))
        payload["approvals"][0]["addressReferenceLatitude"] = "37.9"
        self.approval_path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(StorePublishingError, "너무 멉니다"):
            self._apply()

    def test_uuid_name_address_and_source_place_duplicates_are_rejected(self) -> None:
        mutations = (
            ("storeId", self.publish_rows[0]["storeId"]),
            ("sourcePlaceId", "place_virtual_public_01"),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                self.tearDown()
                self.setUp()
                payload = json.loads(self.approval_path.read_text(encoding="utf-8"))
                payload["approvals"][0][field] = value
                self.approval_path.write_text(json.dumps(payload), encoding="utf-8")
                with self.assertRaisesRegex(StorePublishingError, "중복"):
                    self._apply()

        self.tearDown()
        self.setUp()
        payload = json.loads(self.approval_path.read_text(encoding="utf-8"))
        payload["approvals"][0]["name"] = self.publish_rows[0]["name"]
        payload["approvals"][0]["address"] = self.publish_rows[0]["address"]
        self.approval_path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(StorePublishingError, "중복"):
            self._apply()

    def test_partial_application_is_rejected(self) -> None:
        rows = self._apply()
        rows = [row for row in rows if row["candidateId"] != "virtual_hold_current"]
        self._write_csv(self.publish_path, REVIEW_HEADERS, rows)
        with self.assertRaisesRegex(StorePublishingError, "부분 반영"):
            self._apply()

    def test_generates_exact_two_row_guarded_insert_sql(self) -> None:
        self._apply()
        count = sql_tool.generate_phase_6b2_store_sql(
            self.publish_path,
            self.approval_path,
            MIGRATION_PATH,
            self.sql_path,
            today=dt.date(2026, 8, 26),
        )
        sql = self.sql_path.read_text(encoding="utf-8")
        self.assertEqual(count, 2)
        self.assertIn("public_count <> 23", sql)
        self.assertIn("inserted_count <> 2", sql)
        self.assertIn("public_count <> 25", sql)
        self.assertIn("matched_count <> 2", sql)
        self.assertEqual(sql.lower().count("timestamptz "), 2)
        self.assertNotRegex(sql.lower(), r"\b(update|delete|upsert|rpc)\b|on\s+conflict")
        for approval in self.fixture["approvals"]:
            self.assertNotIn(approval["candidateId"], sql)
            self.assertNotIn(approval["sourcePlaceId"], sql)
            for evidence in approval["evidence"]:
                self.assertNotIn(evidence["url"], sql)
        self.assertNotIn(self.fixture["excluded"][0]["name"], sql)

    def test_existing_sql_must_be_identical(self) -> None:
        self._apply()
        arguments = (
            self.publish_path,
            self.approval_path,
            MIGRATION_PATH,
            self.sql_path,
        )
        sql_tool.generate_phase_6b2_store_sql(
            *arguments, today=dt.date(2026, 8, 26)
        )
        first_hash = self._sha(self.sql_path)
        sql_tool.generate_phase_6b2_store_sql(
            *arguments, today=dt.date(2026, 8, 26)
        )
        self.assertEqual(self._sha(self.sql_path), first_hash)
        self.sql_path.write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(StorePublishingError, "덮어쓰지"):
            sql_tool.generate_phase_6b2_store_sql(
                *arguments, today=dt.date(2026, 8, 26)
            )

    def test_sql_contains_no_credentials_or_internal_identifiers(self) -> None:
        self._apply()
        sql_tool.generate_phase_6b2_store_sql(
            self.publish_path,
            self.approval_path,
            MIGRATION_PATH,
            self.sql_path,
            today=dt.date(2026, 8, 26),
        )
        sql = self.sql_path.read_text(encoding="utf-8")
        self.assertIsNone(
            re.search(
                r"AIza[0-9A-Za-z_-]{30,}|sb_(?:publishable|secret)_|"
                r"eyJ[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+\.[0-9A-Za-z_-]+|"
                r"https://[a-z0-9]{15,}\.supabase\.co",
                sql,
            )
        )


if __name__ == "__main__":
    unittest.main()
