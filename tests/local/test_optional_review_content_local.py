"""Run the optional-review contract against the dedicated disposable local stack.

No production configuration is read. Local keys stay in this process, and all
synthetic rows and Auth users are removed even when an assertion fails.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

from run_auth_menu_reviews_security_revalidation import (
    LocalApi,
    create_profile,
    require,
)


ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "build" / "review_mvp_local_20260928_0600"
CONTAINER = "supabase_db_review_mvp_local_20260928_0600"
API_URLS = {"http://127.0.0.1:59321", "http://localhost:59321"}


def docker_cli() -> Path:
    executable = shutil.which("docker")
    if executable:
        return Path(executable)
    local_app_data = os.environ.get("LOCALAPPDATA")
    require(bool(local_app_data), "Docker CLI unavailable")
    return Path(local_app_data) / "Programs" / "DockerDesktop" / "resources" / "bin" / "docker.exe"


DOCKER = docker_cli()


def local_config() -> None:
    require(PROJECT.is_dir(), "dedicated local project missing")
    require(DOCKER.is_file(), "Docker CLI unavailable")
    result = subprocess.run(
        ["npx.cmd", "supabase@2.117.0", "status", "-o", "env"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=45,
        check=False,
        env={**os.environ, "PATH": str(DOCKER.parent) + os.pathsep + os.environ["PATH"]},
    )
    # Never include CLI stdout/stderr in errors: they can contain local keys.
    require(result.returncode == 0, "dedicated local status unavailable")
    values = {}
    for line in result.stdout.splitlines():
        if re.match(r"^[A-Z_]+=", line):
            name, value = line.split("=", 1)
            values[name] = value.strip().strip('"')
    require(values.get("API_URL") in API_URLS, "refusing unexpected API URL")
    require(bool(values.get("ANON_KEY")), "local anon key missing")
    require(bool(values.get("SERVICE_ROLE_KEY")), "local service key missing")
    os.environ.update(
        SUPABASE_LOCAL_API_URL=values["API_URL"],
        SUPABASE_LOCAL_ANON_KEY=values["ANON_KEY"],
        SUPABASE_LOCAL_SERVICE_KEY=values["SERVICE_ROLE_KEY"],
        SUPABASE_LOCAL_DB_CONTAINER=CONTAINER,
        SUPABASE_LOCAL_DOCKER=str(DOCKER),
    )


def uid(value: str) -> str:
    return str(uuid.UUID(value))


def fixture_store(api: LocalApi, label: str, stores: list[str]) -> str:
    store_id = str(uuid.uuid4())
    stores.append(store_id)
    api.service_insert("stores", {
        "id": store_id,
        "name": f"Local optional review {label}",
        "address": "Yongsan local fixture",
        "latitude": 37.53,
        "longitude": 126.98,
        "verification_status": "verified",
        "is_active": True,
        "source_type": "manual_review",
        "verified_at": "2026-09-28T00:00:00Z",
    })
    return store_id


def fixture_signup(api: LocalApi, label: str, users: list[str], emails: list[str]) -> tuple[str, str]:
    email = f"review-optional-{label}-{uuid.uuid4().hex}@local.invalid"
    emails.append(email)
    status, body, _ = api.request(
        "POST", "/auth/v1/signup",
        payload={"email": email, "password": f"Local!{uuid.uuid4().hex}"},
    )
    require(status in {200, 201} and isinstance(body, dict), "local Auth signup failed")
    user_id = body.get("user", {}).get("id")
    token = body.get("access_token")
    require(isinstance(user_id, str) and isinstance(token, str),
            "local Auth signup response incomplete")
    users.append(uid(user_id))
    return user_id, token


def sql_literal(value: str | None) -> str:
    if value is None:
        return "NULL"
    return "'" + value.replace("'", "''") + "'"


def psql(sql: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            str(DOCKER), "exec", "-i", CONTAINER, "psql", "-X", "-qAt",
            "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=sqlstate",
            "-U", "postgres", "-d", "postgres",
        ],
        input=sql,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=30,
        check=False,
    )


def sql_case(label: str, statements: str, *, error: str | None = None) -> None:
    result = psql("BEGIN;\n" + statements + "\nROLLBACK;")
    if error is None:
        states = re.findall(r"\b[0-9A-Z]{5}\b", result.stderr)
        require(result.returncode == 0, f"{label}: expected SQL success (SQLSTATE {states[:2]})")
    else:
        require(result.returncode != 0 and error in result.stderr,
                f"{label}: expected SQLSTATE {error}")
    print(f"SQL {label}: PASS")


def review_insert(store: str, user: str, rating: str, content: str | None) -> str:
    return (
        "INSERT INTO public.reviews (store_id,user_id,rating,content) "
        f"VALUES ('{uid(store)}','{uid(user)}',{rating},{sql_literal(content)});"
    )


def sql_contract(store_a: str, store_b: str, user_a: str, user_b: str) -> int:
    cases = 0
    for label, content, error in (
        ("content NULL", None, None),
        ("content 10 Korean chars", "가" * 10, None),
        ("content 2000 Korean chars", "가" * 2000, None),
        ("content 10 Unicode emoji", "🍔" * 10, None),
        ("content empty", "", "23514"),
        ("content whitespace", " \t\r\n", "23514"),
        ("content 2001 chars", "가" * 2001, "23514"),
    ):
        sql_case(label, review_insert(store_a, user_a, "3", content), error=error)
        cases += 1
    for length in range(1, 10):
        sql_case(f"content {length} chars",
                 review_insert(store_a, user_a, "3", "가" * length), error="23514")
        cases += 1
    for rating in range(1, 6):
        sql_case(f"rating {rating}", review_insert(store_a, user_a, str(rating), None))
        cases += 1
    for rating, error in (("0", "23514"), ("6", "23514"), ("NULL", "23502")):
        sql_case(f"rating {rating}", review_insert(store_a, user_a, rating, None), error=error)
        cases += 1
    sql_case("UNIQUE same user/store", review_insert(store_a, user_a, "4", None)
             + review_insert(store_a, user_a, "5", None), error="23505")
    sql_case("UNIQUE different store", review_insert(store_a, user_a, "4", None)
             + review_insert(store_b, user_a, "5", None))
    sql_case("UNIQUE different user", review_insert(store_a, user_a, "4", None)
             + review_insert(store_a, user_b, "5", None))
    cases += 3
    invalid = "99999999-9999-4999-8999-999999999999"
    sql_case("FK unknown store", review_insert(invalid, user_a, "4", None), error="23503")
    sql_case("FK unknown profile", review_insert(store_a, invalid, "4", None), error="23503")
    return cases + 2


def rest_contract(api: LocalApi, store_a: str, store_b: str,
                  user_a: str, token_a: str, user_b: str, token_b: str) -> int:
    count = 0

    def check(condition: bool, label: str) -> None:
        nonlocal count
        api.check(condition, label)
        count += 1
        print(f"REST {label}: PASS")

    path = "/rest/v1/reviews?select=id,store_id,user_id,rating,content"
    status, rows, _ = api.request(
        "POST", path, token=token_a,
        payload={"store_id": store_a, "rating": 5, "content": None},
        headers={"Prefer": "return=representation"},
    )
    check(status == 201 and isinstance(rows, list) and len(rows) == 1
          and rows[0]["user_id"] == user_a and rows[0]["content"] is None,
          "A own NULL-content INSERT")
    own_id = uid(rows[0]["id"])
    status, rows, _ = api.request(
        "POST", path, token=token_b,
        payload={"store_id": store_a, "rating": 4, "content": "Valid local review text"},
        headers={"Prefer": "return=representation"},
    )
    check(status == 201 and isinstance(rows, list) and len(rows) == 1
          and rows[0]["user_id"] == user_b, "B own INSERT")
    other_id = uid(rows[0]["id"])
    original_other = api.snapshot_review(other_id)
    status, rows, _ = api.request(
        "GET", f"/rest/v1/public_reviews?select=id,content&id=eq.{own_id}")
    check(status == 200 and rows == [{"id": own_id, "content": None}],
          "anon reads public NULL-content review")
    status, rows, _ = api.request(
        "GET", f"/rest/v1/reviews?select=id,content&id=eq.{own_id}")
    check(status == 200 and rows == [{"id": own_id, "content": None}],
          "anon direct reviews SELECT")
    status, _, _ = api.request(
        "POST", path, token=token_a,
        payload={"store_id": store_b, "user_id": user_b, "rating": 5, "content": None},
        headers={"Prefer": "return=representation"},
    )
    check(status in {401, 403}, "A spoofed B INSERT denied")
    check(api.service_rows("reviews", f"store_id=eq.{store_b}&select=id") == [],
          "spoofed INSERT left no row")
    status, _, _ = api.minimal_mutation(
        "PATCH", f"/rest/v1/reviews?id=eq.{own_id}", token_a,
        {"rating": 3, "content": None},
    )
    check(status in {200, 204} and api.snapshot_review(own_id)["rating"] == 3,
          "A own UPDATE")
    status, _, headers = api.minimal_mutation(
        "PATCH", f"/rest/v1/reviews?id=eq.{other_id}", token_a,
        {"rating": 1},
    )
    check(status in {200, 204} and api.zero_rows(headers)
          and api.snapshot_review(other_id) == original_other,
          "A other UPDATE zero rows and unchanged")
    status, _, headers = api.minimal_mutation(
        "DELETE", f"/rest/v1/reviews?id=eq.{other_id}", token_a,
    )
    check(status in {200, 204} and api.zero_rows(headers)
          and api.snapshot_review(other_id) == original_other,
          "A other DELETE zero rows and unchanged")
    status, _, _ = api.minimal_mutation(
        "DELETE", f"/rest/v1/reviews?id=eq.{own_id}", token_a,
    )
    check(status in {200, 204} and api.service_rows("reviews", f"id=eq.{own_id}&select=id") == [],
          "A own DELETE")
    return count


def cleanup(users: list[str], stores: list[str], emails: list[str]) -> None:
    user_ids = ",".join(f"'{uid(value)}'" for value in users)
    store_ids = ",".join(f"'{uid(value)}'" for value in stores)
    email_values = ",".join(sql_literal(value) for value in emails)
    statements = ["BEGIN;"]
    if store_ids:
        statements += [f"DELETE FROM public.reviews WHERE store_id IN ({store_ids});",
                       f"DELETE FROM public.stores WHERE id IN ({store_ids});"]
    if email_values:
        statements.append(f"DELETE FROM auth.users WHERE email IN ({email_values});")
    statements += ["COMMIT;"]
    result = psql("\n".join(statements))
    require(result.returncode == 0, "local fixture cleanup failed")
    checks = []
    for table, column, ids in (
        ("auth.users", "id", user_ids),
        ("public.profiles", "id", user_ids),
        ("public.stores", "id", store_ids),
        ("public.reviews", "store_id", store_ids),
        ("public.review_reports", "reporter_user_id", user_ids),
    ):
        if ids:
            checks.append(f"SELECT count(*) FROM {table} WHERE {column} IN ({ids});")
    if email_values:
        checks.append(f"SELECT count(*) FROM auth.users WHERE email IN ({email_values});")
    result = psql("\n".join(checks))
    require(result.returncode == 0 and all(line == "0" for line in result.stdout.splitlines()),
            "local fixture cleanup verification failed")
    print("LOCAL fixture cleanup: PASS")


def main() -> int:
    local_config()
    api = LocalApi()
    require(api.container == CONTAINER and api.url in API_URLS,
            "refusing non-dedicated local target")
    users: list[str] = []
    stores: list[str] = []
    emails: list[str] = []
    try:
        user_a, token_a = fixture_signup(api, "a", users, emails)
        user_b, token_b = fixture_signup(api, "b", users, emails)
        create_profile(api, token_a, user_a, "ReviewLocalA")
        create_profile(api, token_b, user_b, "ReviewLocalB")
        store_a = fixture_store(api, "A", stores)
        store_b = fixture_store(api, "B", stores)
        sql_count = sql_contract(store_a, store_b, user_a, user_b)
        rest_count = rest_contract(api, store_a, store_b, user_a, token_a, user_b, token_b)
        print(f"LOCAL SQL contracts: {sql_count}/{sql_count} PASS")
        print(f"LOCAL REST/Auth contracts: {rest_count}/{rest_count} PASS")
    finally:
        try:
            cleanup(users, stores, emails)
        finally:
            for name in ("SUPABASE_LOCAL_ANON_KEY", "SUPABASE_LOCAL_SERVICE_KEY"):
                os.environ.pop(name, None)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        # Keep diagnostics free of HTTP bodies, SQL text, tokens and keys.
        print(f"LOCAL contract FAILED: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
