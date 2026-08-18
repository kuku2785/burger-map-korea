from __future__ import annotations

import re
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
MIGRATION_PATH = (
    PROJECT_ROOT / "supabase" / "migrations" / "0001_init_store_schema.sql"
)
DATABASE_DOC_PATH = PROJECT_ROOT / "docs" / "database-schema.md"
DATA_POLICY_PATH = PROJECT_ROOT / "docs" / "data-source-policy.md"


class StoreSchemaMigrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION_PATH.read_text(encoding="utf-8")
        cls.normalized_sql = re.sub(r"\s+", " ", cls.sql.lower()).strip()
        match = re.search(
            r"create\s+table\s+public\.stores\s*\((.*?)\n\);",
            cls.sql,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if match is None:
            raise AssertionError("public.stores table definition was not found")
        cls.table_body = match.group(1)

    def test_migration_and_documentation_files_exist(self) -> None:
        self.assertTrue(MIGRATION_PATH.is_file())
        self.assertTrue(DATABASE_DOC_PATH.is_file())
        self.assertTrue(DATA_POLICY_PATH.is_file())

    def test_stores_has_required_columns(self) -> None:
        required_columns = {
            "id",
            "name",
            "address",
            "latitude",
            "longitude",
            "burger_style",
            "verification_status",
            "is_active",
            "source_type",
            "source_as_of",
            "verified_at",
            "created_at",
            "updated_at",
        }
        column_names = {
            match.group(1).lower()
            for match in re.finditer(
                r"^\s{2}([a-z_][a-z0-9_]*)\s+[a-z]",
                self.table_body,
                flags=re.IGNORECASE | re.MULTILINE,
            )
        }
        self.assertTrue(required_columns.issubset(column_names))

    def test_id_is_internal_uuid_primary_key(self) -> None:
        self.assertRegex(
            self.normalized_sql,
            r"id uuid primary key default gen_random_uuid\(\)",
        )

    def test_text_and_coordinate_constraints(self) -> None:
        self.assertRegex(self.normalized_sql, r"name text not null")
        self.assertRegex(self.normalized_sql, r"address text not null")
        self.assertIn("btrim(name) <> ''", self.normalized_sql)
        self.assertIn("btrim(address) <> ''", self.normalized_sql)
        self.assertIn("latitude between -90 and 90", self.normalized_sql)
        self.assertIn("longitude between -180 and 180", self.normalized_sql)

    def test_safe_defaults_and_timestamps(self) -> None:
        self.assertIn(
            "verification_status text not null default 'pending'",
            self.normalized_sql,
        )
        self.assertIn("is_active boolean not null default false", self.normalized_sql)
        self.assertIn(
            "created_at timestamp with time zone not null default now()",
            self.normalized_sql,
        )
        self.assertIn(
            "updated_at timestamp with time zone not null default now()",
            self.normalized_sql,
        )

    def test_verification_status_and_verified_at_constraints(self) -> None:
        for status in ("pending", "needs_recheck", "verified", "rejected"):
            self.assertIn(f"'{status}'", self.normalized_sql)
        self.assertIn(
            "verification_status = 'verified' and verified_at is not null",
            self.normalized_sql,
        )
        self.assertIn(
            "verification_status <> 'verified' and verified_at is null",
            self.normalized_sql,
        )

    def test_updated_at_function_and_trigger_exist(self) -> None:
        self.assertIn(
            "create or replace function public.set_stores_updated_at()",
            self.normalized_sql,
        )
        self.assertIn("new.updated_at = now()", self.normalized_sql)
        self.assertRegex(
            self.normalized_sql,
            r"create trigger stores_set_updated_at before update on public\.stores",
        )

    def test_rls_and_public_read_policy_are_restrictive(self) -> None:
        self.assertIn(
            "alter table public.stores enable row level security",
            self.normalized_sql,
        )
        policies = re.findall(
            r"create\s+policy\s+.*?;",
            self.normalized_sql,
            flags=re.DOTALL,
        )
        self.assertEqual(len(policies), 1)
        policy = policies[0]
        self.assertIn("for select", policy)
        self.assertIn("to anon, authenticated", policy)
        self.assertIn("verification_status = 'verified'", policy)
        self.assertIn("is_active = true", policy)
        for operation in ("insert", "update", "delete", "all"):
            self.assertNotRegex(policy, rf"for\s+{operation}\b")

    def test_public_roles_have_select_only(self) -> None:
        self.assertIn(
            "revoke all privileges on table public.stores from anon, authenticated",
            self.normalized_sql,
        )
        self.assertIn(
            "grant select on table public.stores to anon, authenticated",
            self.normalized_sql,
        )
        self.assertNotRegex(
            self.normalized_sql,
            r"grant\s+(insert|update|delete|all).*?\b(anon|authenticated)\b",
        )

    def test_no_external_place_columns_or_store_seed(self) -> None:
        lowered_table = self.table_body.lower()
        for forbidden in (
            "kakao_place_id",
            "google_place_id",
            "external_place_id",
            "place_url",
        ):
            self.assertNotIn(forbidden, lowered_table)
        self.assertNotRegex(
            self.normalized_sql,
            r"insert\s+into\s+public\.stores\b",
        )

    def test_phase_3a_files_do_not_contain_real_key_patterns(self) -> None:
        content = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (MIGRATION_PATH, DATABASE_DOC_PATH, DATA_POLICY_PATH)
        )
        patterns = (
            r"AIza[0-9A-Za-z_-]{35}",
            r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+",
            r"sb_(?:publishable|secret)_[A-Za-z0-9_-]{20,}",
        )
        for pattern in patterns:
            self.assertIsNone(re.search(pattern, content))


if __name__ == "__main__":
    unittest.main()
