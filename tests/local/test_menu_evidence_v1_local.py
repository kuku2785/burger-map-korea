"""SQL contract for an isolated, fresh LOCAL Supabase database only.

Set MENU_EVIDENCE_LOCAL_CONTAINER to the exact dedicated DB container name.
Each fixture runs in its own transaction and is rolled back on success or error.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "build_menu_pipeline_v1_local_contract",
    ROOT / "scripts" / "data" / "build_menu_pipeline_v1.py",
)
assert spec and spec.loader
pipeline = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pipeline
spec.loader.exec_module(pipeline)


CONTAINER = "supabase_db_menu_evidence_v1_local_20260924_1406"
STORE_A = "10000000-0000-4000-8000-000000000001"
STORE_B = "10000000-0000-4000-8000-000000000002"
STORE_C = "10000000-0000-4000-8000-000000000003"
MENU_A = "20000000-0000-4000-8000-000000000001"
MENU_B = "20000000-0000-4000-8000-000000000002"
MENU_INACTIVE = "20000000-0000-4000-8000-000000000003"
UNKNOWN = "99999999-9999-4999-8999-999999999999"

FIXTURE = f"""
BEGIN;
INSERT INTO public.stores
  (id, name, address, latitude, longitude, verification_status,
   is_active, source_type, verified_at)
VALUES
  ('{STORE_A}', 'Local A', 'Test Street 1', 37.5, 127.0,
   'verified', true, 'manual_review', now()),
  ('{STORE_B}', 'Local B', 'Test Street 2', 37.5, 127.0,
   'pending', false, 'manual_review', NULL);
INSERT INTO public.menus (id, store_id, name, price, is_active)
VALUES
  ('{MENU_A}', '{STORE_A}', 'A Burger', NULL, true),
  ('{MENU_B}', '{STORE_B}', 'B Burger', NULL, true),
  ('{MENU_INACTIVE}', '{STORE_A}', 'Hidden Burger', NULL, false);
"""


def evidence_insert(
    *,
    store_id: str = STORE_A,
    menu_id: str | None = None,
    source_url: str = "https://example.org/local-test-menu",
    source_type: str = "official_store_page",
    source_tier: str = "A",
    match: str = "EXACT_MATCH",
    price: int | None = 10800,
    context: str = "order_channel",
    currentness: str = "UNKNOWN",
    normalized_name: str = "a burger",
    published_at: str | None = None,
    status: str = "candidate",
    approval_ref: str | None = None,
) -> str:
    """Only hard-coded synthetic test values are passed to this SQL builder."""
    menu = f"'{menu_id}'" if menu_id else "NULL"
    observed_price = str(price) if price is not None else "NULL"
    published = f"'{published_at}'" if published_at else "NULL"
    approval = f"'{approval_ref}'" if approval_ref else "NULL"
    return f"""
INSERT INTO burger_map_private.menu_evidence
  (store_id, menu_id, source_url, source_type, source_tier,
   store_match_status, observed_name, normalized_name,
   observed_price_krw, price_context, currentness,
   source_published_at, retrieved_at, evidence_status, approval_ref)
VALUES
  ('{store_id}', {menu}, '{source_url}',
   '{source_type}', '{source_tier}', '{match}',
   'A Burger', '{normalized_name}', {observed_price}, '{context}',
   '{currentness}', {published}, now(), '{status}', {approval});
"""


def psql(sql: str) -> subprocess.CompletedProcess[str]:
    if os.environ.get("MENU_EVIDENCE_LOCAL_CONTAINER") != CONTAINER:
        pytest.skip("dedicated local Supabase container not selected")
    result = subprocess.run(
        [
            "docker",
            "exec",
            "-i",
            CONTAINER,
            "psql",
            "-X",
            "-qAt",
            "-v",
            "ON_ERROR_STOP=1",
            "-v",
            "VERBOSITY=sqlstate",
            "-U",
            "postgres",
            "-d",
            "postgres",
        ],
        input=sql,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    return result


def expect_ok(sql: str, expected: str | None = None) -> None:
    result = psql(sql)
    assert result.returncode == 0, result.stderr
    if expected is not None:
        assert result.stdout.strip() == expected


def expect_denied(sql: str, sqlstate: str) -> None:
    result = psql(sql)
    assert result.returncode != 0, result.stdout
    assert sqlstate in result.stderr, result.stderr


def test_nullable_menu_and_observed_order_price():
    expect_ok(
        FIXTURE
        + evidence_insert()
        + """
SELECT menu_id IS NULL, observed_price_krw = 10800,
       price_context = 'order_channel', source_published_at IS NULL
FROM burger_map_private.menu_evidence;
ROLLBACK;
""",
        "t|t|t|t",
    )


def test_matching_menu_and_allowed_lifecycle_values():
    expect_ok(
        FIXTURE
        + evidence_insert(menu_id=MENU_A, status="approved", approval_ref="review-1")
        + evidence_insert(
            status="rejected", source_type="delivery_platform", source_tier="B"
        )
        + evidence_insert(
            status="superseded", source_type="kakao_place", source_tier="C"
        )
        + """
SELECT count(*), count(*) FILTER (WHERE menu_id IS NOT NULL),
       count(*) FILTER (WHERE observed_price_krw = 10800)
FROM burger_map_private.menu_evidence;
ROLLBACK;
""",
        "3|1|3",
    )


def test_all_allowed_source_types_insert():
    source_types = (
        "official_website",
        "official_store_page",
        "official_brand_page",
        "official_social",
        "official_order",
        "business_profile",
        "delivery_platform",
        "reservation_platform",
        "kakao_place",
        "naver_place",
        "third_party_review",
        "blog",
        "unknown",
    )
    inserts = "".join(evidence_insert(source_type=kind) for kind in source_types)
    expect_ok(
        FIXTURE
        + inserts
        + "SELECT count(*) FROM burger_map_private.menu_evidence;\nROLLBACK;",
        str(len(source_types)),
    )


@pytest.mark.parametrize(
    ("kwargs", "sqlstate"),
    [
        (
            {
                "store_id": STORE_A,
                "menu_id": MENU_B,
                "status": "approved",
                "approval_ref": "r",
            },
            "23503",
        ),
        ({"store_id": UNKNOWN}, "23503"),
        ({"menu_id": UNKNOWN, "status": "approved", "approval_ref": "r"}, "23503"),
        ({"source_type": "invalid"}, "23514"),
        ({"source_url": "ftp://example.org/menu"}, "23514"),
        ({"source_tier": "D"}, "23514"),
        ({"match": "wrong"}, "23514"),
        ({"normalized_name": ""}, "23514"),
        ({"status": "auto_published"}, "23514"),
        ({"status": "approved"}, "23514"),
        ({"menu_id": MENU_A, "status": "approved", "approval_ref": " "}, "23514"),
        ({"price": -1}, "23514"),
        ({"context": "guess"}, "23514"),
        ({"currentness": "CURRENT"}, "23514"),
    ],
)
def test_invalid_evidence_rejected(kwargs: dict, sqlstate: str):
    expect_denied(FIXTURE + evidence_insert(**kwargs), sqlstate)


def test_null_price_and_publication_date_allowed():
    expect_ok(
        FIXTURE
        + evidence_insert(price=None, published_at=None)
        + """
SELECT observed_price_krw IS NULL, source_published_at IS NULL,
       retrieved_at IS NOT NULL
FROM burger_map_private.menu_evidence;
ROLLBACK;
""",
        "t|t|t",
    )


def test_fk_delete_update_restrict_and_unique_target():
    expect_ok(
        """
SELECT count(*) = 2
FROM pg_constraint
WHERE conrelid = 'burger_map_private.menu_evidence'::regclass
  AND contype = 'f' AND confdeltype = 'r' AND confupdtype = 'r';
""",
        "t",
    )
    expect_ok(
        """
SELECT count(*) = 1
FROM pg_constraint
WHERE conrelid = 'public.menus'::regclass
  AND conname = 'menus_store_id_id_unique' AND contype = 'u';
""",
        "t",
    )
    expect_denied(
        FIXTURE
        + evidence_insert(menu_id=MENU_A, status="approved", approval_ref="review-1")
        + f"DELETE FROM public.menus WHERE id = '{MENU_A}';",
        "23503",
    )
    expect_denied(
        FIXTURE
        + evidence_insert(menu_id=MENU_A, status="approved", approval_ref="review-1")
        + f"UPDATE public.menus SET store_id = '{STORE_B}' WHERE id = '{MENU_A}';",
        "23503",
    )
    expect_denied(
        FIXTURE
        + f"""
INSERT INTO public.stores
  (id, name, address, latitude, longitude, verification_status, is_active, source_type)
VALUES ('{STORE_C}', 'Local C', 'Test Street 3', 37.5, 127.0,
        'pending', false, 'manual_review');
"""
        + evidence_insert(store_id=STORE_C)
        + f"DELETE FROM public.stores WHERE id = '{STORE_C}';",
        "23503",
    )


def test_private_grants_rls_and_no_client_policy():
    expect_ok(
        """
SELECT has_schema_privilege('anon', 'burger_map_private', 'USAGE'),
       has_schema_privilege('authenticated', 'burger_map_private', 'USAGE'),
       has_table_privilege('anon', 'burger_map_private.menu_evidence', 'SELECT'),
       has_table_privilege('authenticated', 'burger_map_private.menu_evidence', 'SELECT'),
       has_table_privilege('service_role', 'burger_map_private.menu_evidence', 'DELETE'),
       (SELECT relrowsecurity FROM pg_class
        WHERE oid = 'burger_map_private.menu_evidence'::regclass),
       (SELECT count(*) FROM pg_policies
        WHERE schemaname = 'burger_map_private' AND tablename = 'menu_evidence');
""",
        "f|t|f|f|f|t|0",
    )


@pytest.mark.parametrize("role", ["anon", "authenticated"])
@pytest.mark.parametrize("action", ["SELECT", "INSERT", "UPDATE", "DELETE"])
def test_client_roles_cannot_access_private_table(role: str, action: str):
    commands = {
        "SELECT": "SELECT count(*) FROM burger_map_private.menu_evidence;",
        "INSERT": evidence_insert(),
        "UPDATE": "UPDATE burger_map_private.menu_evidence SET notes = 'x';",
        "DELETE": "DELETE FROM burger_map_private.menu_evidence;",
    }
    expect_denied(FIXTURE + f"SET LOCAL ROLE {role};\n" + commands[action], "42501")


def test_service_role_can_read_and_write_but_not_delete():
    expect_ok(
        FIXTURE
        + "SET LOCAL ROLE service_role;\n"
        + evidence_insert()
        + """
UPDATE burger_map_private.menu_evidence SET notes = 'checked';
SELECT count(*) FROM burger_map_private.menu_evidence WHERE notes = 'checked';
ROLLBACK;
""",
        "1",
    )
    expect_denied(
        FIXTURE
        + evidence_insert()
        + "SET LOCAL ROLE service_role;\n"
        + "DELETE FROM burger_map_private.menu_evidence;",
        "42501",
    )


@pytest.mark.parametrize("role", ["anon", "authenticated"])
def test_public_store_and_menu_visibility_unchanged(role: str):
    expect_ok(
        FIXTURE
        + f"SET LOCAL ROLE {role};\n"
        + """
SELECT (SELECT count(*) FROM public.stores),
       (SELECT count(*) FROM public.menus),
       (SELECT count(*) FROM public.menus WHERE price IS NULL);
ROLLBACK;
""",
        "1|1|1",
    )


def test_candidate_to_approved_decision_proposes_null_public_price():
    result = psql(
        FIXTURE
        + evidence_insert()
        + """
SELECT evidence_status, observed_price_krw, price_context, menu_id IS NULL
FROM burger_map_private.menu_evidence;
"""
        + f"""
UPDATE burger_map_private.menu_evidence
SET menu_id = '{MENU_A}', evidence_status = 'approved', approval_ref = 'review-1';
SELECT evidence_status, approval_ref, menu_id = '{MENU_A}'
FROM burger_map_private.menu_evidence;
ROLLBACK;
"""
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip().splitlines() == [
        "candidate|10800|order_channel|t",
        "approved|review-1|t",
    ]
    review = {
        "store_id": STORE_A,
        "row_type": "MENU",
        "menu_name": "A Burger",
        "observed_price_krw": 10800,
        "price_context": "order_channel",
        "source_tier": "A",
        "store_match_status": "EXACT_MATCH",
        "review_status": "QUICK_REVIEW",
    }
    checks = {
        "approved_by": "local-reviewer",
        "approved_at": "2026-09-25",
        "approval_ref": "review-1",
        "name_verified": True,
        "source_access_verified": True,
        "source_current_verified": True,
        "store_public_verified": True,
        "fk_verified": True,
        "duplicate_free": True,
        "dry_run_passed": True,
    }
    with pytest.raises(ValueError, match="explicit human approval"):
        pipeline.plan_approved_menu(review, checks)
    proposal = pipeline.plan_approved_menu(review, {**checks, "approved": True})
    assert proposal["approval_ref"] == "review-1"
    assert proposal["menu"]["price"] is None
    assert proposal["menu"]["name"] == "A Burger"
    expect_ok("SELECT count(*) FROM public.menus;", "0")
