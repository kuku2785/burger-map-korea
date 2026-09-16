#!/usr/bin/env python3
"""Validate a synthetic Gangbuk publish review fixture."""

from __future__ import annotations

import csv
import datetime as dt
import math
import sys
import unittest
import uuid
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = PROJECT_ROOT / "scripts" / "data"
FIXTURE_DIR = PROJECT_ROOT / "tests" / "fixtures" / "gangbuk_publish_review"
REVIEW_PATH = FIXTURE_DIR / "review.csv"
AUDIT_PATH = FIXTURE_DIR / "audit.csv"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from store_publishing_common import (  # noqa: E402
    ALLOWED_REVIEW_DECISIONS,
    REVIEW_HEADERS,
    STORE_INSERT_COLUMNS,
)

ALLOWED_STYLES = {
    "classic", "smash", "chicken", "plant_based", "other", "unclassified", ""
}
ALLOWED_SOURCE_TYPES = {
    "public_data", "manual_review", "user_submission", "owner_submission", "mixed"
}
EXCLUDED_CHAIN_KEYWORDS = (
    "맥도날드", "롯데리아", "버거킹", "맘스터치", "kfc", "케이에프씨",
    "노브랜드버거", "버거리", "프랭크버거", "왓더버거", "움버거앤윙스",
    "버거앤타코", "봉구스밥버거", "뚱스밥버거", "쉐프밥버거", "패티앤빅", "파파존스",
)


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as input_file:
        reader = csv.DictReader(input_file)
        return list(reader.fieldnames or []), list(reader)


def validate_review(
    headers: list[str], rows: list[dict[str, str]], audit_rows: list[dict[str, str]]
) -> list[str]:
    """Return all publish-readiness failures without touching production data."""
    failures: list[str] = []
    if headers != list(REVIEW_HEADERS):
        failures.append(f"Review headers do not match canonical schema: {headers}")
    if not rows:
        failures.append("Review file has 0 data rows")

    audit_by_candidate: dict[str, list[dict[str, str]]] = {}
    for audit_row in audit_rows:
        audit_by_candidate.setdefault(audit_row.get("candidateId", ""), []).append(audit_row)

    seen_candidate_ids: set[str] = set()
    seen_store_ids: set[str] = set()
    active_stores: list[tuple[str, str, float, float, str]] = []

    for line_number, row in enumerate(rows, start=2):
        candidate_id = row.get("candidateId", "").strip()
        store_id = row.get("storeId", "").strip()
        name = row.get("name", "").strip()
        address = row.get("address", "").strip()
        latitude_text = row.get("latitude", "").strip()
        longitude_text = row.get("longitude", "").strip()
        style = row.get("burgerStyle", "").strip()
        source_type = row.get("sourceType", "").strip()
        source_as_of = row.get("sourceAsOf", "").strip()
        decision = row.get("publishDecision", "").strip()
        is_active = row.get("isActive", "").strip()
        verified_at = row.get("verifiedAt", "").strip()

        if not candidate_id:
            failures.append(f"Row {line_number}: empty candidateId")
        elif candidate_id in seen_candidate_ids:
            failures.append(f"Row {line_number}: duplicate candidateId {candidate_id}")
        seen_candidate_ids.add(candidate_id)

        try:
            parsed_uuid = uuid.UUID(store_id)
            if str(parsed_uuid) != store_id:
                failures.append(f"Row {line_number}: storeId not canonical UUID {store_id}")
        except (ValueError, AttributeError):
            failures.append(f"Row {line_number}: invalid storeId UUID {store_id}")
        if store_id in seen_store_ids:
            failures.append(f"Row {line_number}: duplicate storeId {store_id}")
        seen_store_ids.add(store_id)

        latitude: float | None = None
        longitude: float | None = None
        try:
            latitude = float(latitude_text)
            longitude = float(longitude_text)
            if not (37.0 <= latitude <= 38.0 and 126.5 <= longitude <= 127.5):
                failures.append(
                    f"Row {line_number}: coordinate out of Seoul bounds ({latitude}, {longitude})"
                )
        except ValueError:
            failures.append(
                f"Row {line_number}: non-numeric coordinates ({latitude_text}, {longitude_text})"
            )

        if "강북구" not in address:
            failures.append(f"Row {line_number}: outside Gangbuk address '{address}'")
        if style not in ALLOWED_STYLES:
            failures.append(f"Row {line_number}: invalid burgerStyle '{style}'")
        if source_type not in ALLOWED_SOURCE_TYPES:
            failures.append(f"Row {line_number}: invalid sourceType '{source_type}'")
        if decision not in ALLOWED_REVIEW_DECISIONS:
            failures.append(f"Row {line_number}: invalid publishDecision '{decision}'")
        if is_active not in {"true", "false"}:
            failures.append(f"Row {line_number}: invalid boolean isActive '{is_active}'")
        if source_as_of:
            try:
                dt.date.fromisoformat(source_as_of)
            except ValueError:
                failures.append(f"Row {line_number}: invalid sourceAsOf date '{source_as_of}'")

        if is_active == "true":
            if decision != "verified":
                failures.append(
                    f"Row {line_number}: active=true but decision is not verified ('{decision}')"
                )
            if not verified_at:
                failures.append(f"Row {line_number}: active=true but verifiedAt is empty")
            else:
                try:
                    parsed_verified_at = dt.datetime.fromisoformat(verified_at)
                    if parsed_verified_at.tzinfo is None:
                        failures.append(f"Row {line_number}: verifiedAt missing timezone")
                except ValueError:
                    failures.append(
                        f"Row {line_number}: invalid verifiedAt ISO format '{verified_at}'"
                    )

            lowered_name = name.lower()
            for keyword in EXCLUDED_CHAIN_KEYWORDS:
                if keyword in lowered_name:
                    failures.append(
                        f"Row {line_number}: active store matches excluded chain keyword "
                        f"'{keyword}': {name}"
                    )

            valid_evidence = [
                evidence for evidence in audit_by_candidate.get(candidate_id, [])
                if evidence.get("evidenceUrl")
                and evidence.get("evidenceUrl") not in {"NO_MATCH", "KEY_RESTRICTED"}
            ]
            if len(valid_evidence) < 2:
                failures.append(
                    f"Row {line_number} ({candidate_id}): verified+active store has "
                    f"{len(valid_evidence)} valid evidences (minimum 2 required)"
                )
            providers = {evidence.get("provider", "").strip() for evidence in valid_evidence}
            providers.discard("")
            if len(providers) < 2:
                failures.append(
                    f"Row {line_number} ({candidate_id}): verified+active store evidence "
                    f"lacks independent providers: {providers}"
                )
            if latitude is not None and longitude is not None:
                active_stores.append((name, address, latitude, longitude, candidate_id))
        elif is_active == "false":
            if decision == "verified":
                failures.append(f"Row {line_number}: active=false but decision is verified")
            if verified_at:
                failures.append(
                    f"Row {line_number}: active=false but verifiedAt is populated '{verified_at}'"
                )

    for left_index, left in enumerate(active_stores):
        for right in active_stores[left_index + 1:]:
            if left[0] == right[0] and left[1] == right[1]:
                failures.append(f"Duplicate active store: {left[4]} and {right[4]}")
            latitude_distance = (left[2] - right[2]) * 111000
            longitude_distance = (left[3] - right[3]) * 88000
            distance = math.sqrt(latitude_distance**2 + longitude_distance**2)
            if distance < 50:
                failures.append(
                    f"Active stores too close ({distance:.1f}m): {left[4]} and {right[4]}"
                )
    return failures


class TestGangbukPublishReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.headers, cls.rows = read_csv(REVIEW_PATH)
        cls.audit_headers, cls.audit_rows = read_csv(AUDIT_PATH)

    def assert_mutation_rejected(self, mutate, expected_message: str) -> None:
        rows = [dict(row) for row in self.rows]
        audit_rows = [dict(row) for row in self.audit_rows]
        mutate(rows, audit_rows)
        failures = validate_review(self.headers, rows, audit_rows)
        self.assertTrue(
            any(expected_message in failure for failure in failures),
            f"Expected rejection containing {expected_message!r}; got {failures}",
        )

    def test_fixture_files_exist(self):
        self.assertTrue(REVIEW_PATH.is_file(), f"File missing: {REVIEW_PATH}")
        self.assertTrue(AUDIT_PATH.is_file(), f"File missing: {AUDIT_PATH}")

    def test_schema_matches_canonical_review_headers(self):
        self.assertEqual(self.headers, list(REVIEW_HEADERS))

    def test_synthetic_fixture_has_zero_failures(self):
        self.assertEqual(validate_review(self.headers, self.rows, self.audit_rows), [])

    def test_malformed_review_mutations_are_rejected(self):
        cases = (
            ("empty candidate id", lambda r, _a: r[0].update(candidateId=""), "empty candidateId"),
            ("duplicate candidate id", lambda r, _a: r[1].update(candidateId=r[0]["candidateId"]), "duplicate candidateId"),
            ("noncanonical UUID", lambda r, _a: r[0].update(storeId="AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"), "storeId not canonical UUID"),
            ("invalid UUID", lambda r, _a: r[0].update(storeId="not-a-uuid"), "invalid storeId UUID"),
            ("duplicate store id", lambda r, _a: r[1].update(storeId=r[0]["storeId"]), "duplicate storeId"),
            ("nonnumeric coordinate", lambda r, _a: r[0].update(latitude="north"), "non-numeric coordinates"),
            ("coordinate outside Seoul", lambda r, _a: r[0].update(latitude="36.5"), "coordinate out of Seoul bounds"),
            ("address outside Gangbuk", lambda r, _a: r[0].update(address="서울특별시 중구 합성로 1"), "outside Gangbuk address"),
            ("invalid burger style", lambda r, _a: r[0].update(burgerStyle="invalid"), "invalid burgerStyle"),
            ("invalid source type", lambda r, _a: r[0].update(sourceType="scraped"), "invalid sourceType"),
            ("invalid publish decision", lambda r, _a: r[2].update(publishDecision="ready"), "invalid publishDecision"),
            ("invalid boolean", lambda r, _a: r[0].update(isActive="yes"), "invalid boolean isActive"),
            ("invalid source date", lambda r, _a: r[0].update(sourceAsOf="2026-02-30"), "invalid sourceAsOf date"),
            ("active row is not verified", lambda r, _a: r[0].update(publishDecision="pending"), "active=true but decision is not verified"),
            ("active row lacks verification timestamp", lambda r, _a: r[0].update(verifiedAt=""), "active=true but verifiedAt is empty"),
            ("verification timestamp lacks timezone", lambda r, _a: r[0].update(verifiedAt="2026-09-15T10:00:00"), "verifiedAt missing timezone"),
            ("invalid verification timestamp", lambda r, _a: r[0].update(verifiedAt="not-a-time"), "invalid verifiedAt ISO format"),
            ("inactive row is verified", lambda r, _a: r[2].update(publishDecision="verified"), "active=false but decision is verified"),
            ("inactive row has verification timestamp", lambda r, _a: r[2].update(verifiedAt="2026-09-15T10:00:00+09:00"), "active=false but verifiedAt is populated"),
            ("excluded chain", lambda r, _a: r[0].update(name="Synthetic KFC Burger"), "active store matches excluded chain keyword"),
            ("duplicate active store", lambda r, _a: r[1].update(name=r[0]["name"], address=r[0]["address"]), "Duplicate active store"),
            ("nearby active coordinate", lambda r, _a: r[1].update(latitude=r[0]["latitude"], longitude=r[0]["longitude"]), "Active stores too close"),
        )
        for label, mutation, expected_message in cases:
            with self.subTest(label):
                self.assert_mutation_rejected(mutation, expected_message)
        for keyword in EXCLUDED_CHAIN_KEYWORDS:
            with self.subTest(excluded_chain=keyword):
                self.assert_mutation_rejected(
                    lambda rows, _audit, name=keyword: rows[0].update(name=name),
                    "active store matches excluded chain keyword",
                )

    def test_missing_or_nonindependent_evidence_is_rejected(self):
        first_candidate = self.rows[0]["candidateId"]

        def remove_one_provider(_rows, audit_rows):
            audit_rows[:] = [row for row in audit_rows if not (
                row["candidateId"] == first_candidate
                and row["provider"] == "synthetic_provider_b"
            )]

        self.assert_mutation_rejected(remove_one_provider, "valid evidences (minimum 2 required)")

        def repeat_provider(_rows, audit_rows):
            for row in audit_rows:
                if row["candidateId"] == first_candidate:
                    row["provider"] = "synthetic_provider_a"

        self.assert_mutation_rejected(repeat_provider, "evidence lacks independent providers")

    def test_empty_review_and_schema_drift_are_rejected(self):
        self.assertIn("Review file has 0 data rows", validate_review(self.headers, [], self.audit_rows))
        failures = validate_review(self.headers[:-1], self.rows, self.audit_rows)
        self.assertTrue(any("canonical schema" in failure for failure in failures), failures)

    def test_supabase_dry_run_schema_mapping(self):
        published_rows = [row for row in self.rows if row["isActive"] == "true"]
        self.assertEqual(len(published_rows), 2)
        simulated_db = []
        for row in published_rows:
            mapped = {
                "id": str(uuid.UUID(row["storeId"])),
                "name": row["name"].strip(),
                "address": row["address"].strip(),
                "latitude": float(row["latitude"]),
                "longitude": float(row["longitude"]),
                "burger_style": row["burgerStyle"].strip() or None,
                "verification_status": row["publishDecision"].strip(),
                "is_active": row["isActive"] == "true",
                "source_type": row["sourceType"].strip(),
                "source_as_of": str(dt.date.fromisoformat(row["sourceAsOf"])),
                "verified_at": dt.datetime.fromisoformat(row["verifiedAt"]).isoformat(),
            }
            self.assertEqual(tuple(mapped), STORE_INSERT_COLUMNS)
            self.assertTrue(mapped["name"] and mapped["address"])
            self.assertTrue(-90 <= mapped["latitude"] <= 90)
            self.assertTrue(-180 <= mapped["longitude"] <= 180)
            if mapped["burger_style"] is not None:
                self.assertTrue(mapped["burger_style"].strip())
            self.assertIn(mapped["verification_status"], {"pending", "needs_recheck", "verified", "rejected"})
            self.assertIn(mapped["source_type"], ALLOWED_SOURCE_TYPES)
            self.assertEqual(mapped["verification_status"], "verified")
            self.assertTrue(mapped["is_active"] and mapped["verified_at"])
            simulated_db.append(mapped)
        self.assertEqual(len(simulated_db), len(published_rows))


if __name__ == "__main__":
    unittest.main()
