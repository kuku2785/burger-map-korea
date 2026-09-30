"""Local-only review-report RLS/REST/moderation contract with fixture cleanup.

Run only with process-scoped credentials from the dedicated local CLI status.
Never reads .env, prints keys/JWTs, or connects to a non-loopback endpoint.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import uuid
from datetime import datetime, timezone

from run_auth_menu_reviews_security_revalidation import LocalApi, require


PROJECT_ID = "review_report_local_20260929_01"
API_URL = "http://127.0.0.1:56321"
DB_CONTAINER = f"supabase_db_{PROJECT_ID}"


def guard() -> LocalApi:
    require(os.environ.get("SUPABASE_LOCAL_PROJECT_ID") == PROJECT_ID, "wrong local project")
    require(os.environ.get("SUPABASE_LOCAL_API_URL") == API_URL, "wrong local API")
    require(
        os.environ.get("SUPABASE_LOCAL_DB_CONTAINER") == DB_CONTAINER,
        "wrong local DB container",
    )
    api = LocalApi()
    result = subprocess.run(
        [api.docker, "inspect", "-f", "{{.State.Running}}", DB_CONTAINER],
        capture_output=True, text=True, timeout=15, check=False,
    )
    require(result.returncode == 0 and result.stdout.strip() == "true", "local DB not running")
    return api


def sql_boolean(api: LocalApi, expression: str, label: str) -> None:
    result = subprocess.run(
        [api.docker, "exec", DB_CONTAINER, "psql", "-X", "-qAt",
         "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres",
         "-c", f"SELECT ({expression}) IS TRUE;"],
        capture_output=True, text=True, encoding="utf-8", timeout=25, check=False,
    )
    require(result.returncode == 0 and result.stdout.strip() == "t", label)


def sql_contract(api: LocalApi) -> int:
    cases = (
        ("fresh migration chain", "(SELECT array_agg(version ORDER BY version) FROM supabase_migrations.schema_migrations) = ARRAY['0001','20260922050439','20260924140656','20260928054821']"),
        ("report RLS enabled", "(SELECT relrowsecurity FROM pg_class WHERE oid='public.review_reports'::regclass)"),
        ("review RLS enabled", "(SELECT relrowsecurity FROM pg_class WHERE oid='public.reviews'::regclass)"),
        ("reporter/review uniqueness", "EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.review_reports'::regclass AND conname='review_reports_one_per_reporter' AND contype='u')"),
        ("five stored reasons", "(SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.review_reports'::regclass AND conname='review_reports_reason_allowed') LIKE '%spam%harassment%personal_information%irrelevant%other%'"),
        ("other requires detail", "EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.review_reports'::regclass AND conname='review_reports_other_needs_detail')"),
        ("own and hidden target excluded", "(SELECT pg_get_expr(polwithcheck,polrelid) FROM pg_policy WHERE polrelid='public.review_reports'::regclass AND polname='review_reports_owner_insert') LIKE '%r.user_id <>%' AND (SELECT pg_get_expr(polwithcheck,polrelid) FROM pg_policy WHERE polrelid='public.review_reports'::regclass AND polname='review_reports_owner_insert') LIKE '%NOT r.is_hidden%'"),
        ("no anon report read", "NOT has_table_privilege('anon','public.review_reports','SELECT')"),
        ("no authenticated report read", "NOT has_table_privilege('authenticated','public.review_reports','SELECT')"),
        ("client inserts reason only", "has_column_privilege('authenticated','public.review_reports','reason','INSERT') AND NOT has_column_privilege('authenticated','public.review_reports','reporter_user_id','INSERT')"),
        ("operator can inspect reports", "has_table_privilege('service_role','public.review_reports','SELECT')"),
        ("public view invokes RLS", "(SELECT reloptions @> ARRAY['security_invoker=true'] FROM pg_class WHERE oid='public.public_reviews'::regclass)"),
        ("public view excludes hidden", "(SELECT pg_get_viewdef('public.public_reviews'::regclass,true)) LIKE '%NOT r.is_hidden%'"),
        ("review hide requires metadata", "EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.reviews'::regclass AND conname='reviews_hidden_requires_moderation')"),
    )
    for label, expression in cases:
        sql_boolean(api, expression, f"SQL {label}")
    return len(cases)


def check(condition: bool, label: str, counts: dict[str, int]) -> None:
    require(condition, label)
    counts["rest"] += 1


def rows(api: LocalApi, table: str, query: str, counts: dict[str, int]) -> list[dict]:
    status, body, _ = api.request("GET", f"/rest/v1/{table}?{query}", service=True)
    check(status == 200 and isinstance(body, list), f"operator {table} read", counts)
    assert isinstance(body, list)
    return body


def signup(api: LocalApi, label: str, users: list[str], counts: dict[str, int]) -> tuple[str, str]:
    status, body, _ = api.request(
        "POST", "/auth/v1/signup",
        payload={"email": f"review-report-{label}-{uuid.uuid4().hex}@local.invalid",
                 "password": f"Local!{uuid.uuid4().hex}"},
    )
    user = body.get("user") if isinstance(body, dict) else None
    user_id = user.get("id") if isinstance(user, dict) else None
    if isinstance(user_id, str):
        users.append(str(uuid.UUID(user_id)))
    token = body.get("access_token") if isinstance(body, dict) else None
    check(status in {200, 201} and isinstance(user_id, str) and isinstance(token, str),
          f"{label} real local Auth JWT", counts)
    assert isinstance(user_id, str) and isinstance(token, str)
    return user_id, token


def rest_contract(api: LocalApi, users: list[str], store_id: str,
                  review_ids: list[str], counts: dict[str, int]) -> None:
    identities = [signup(api, label, users, counts) for label in ("a", "b", "c")]
    for label, (user_id, token) in zip(("a", "b", "c"), identities):
        status, _, _ = api.request(
            "POST", "/rest/v1/profiles", token=token,
            payload={"id": user_id, "nickname": f"report_{label}"},
            headers={"Prefer": "return=minimal"},
        )
        check(status in {200, 201, 204}, f"{label} own profile create", counts)
    a_id, a_token = identities[0]
    b_id, b_token = identities[1]
    c_id, _ = identities[2]
    # stores intentionally has no service_role INSERT grant when automatic
    # exposure is disabled; a trusted local fixture setup owns this row.
    api.sql(f"""
INSERT INTO public.stores
  (id,name,address,latitude,longitude,verification_status,is_active,source_type,verified_at)
VALUES ('{uuid.UUID(store_id)}','Local Report Burger','Yongsan local fixture',
        37.53,126.98,'verified',true,'manual_review',now());
""")
    sql_boolean(api, f"EXISTS (SELECT 1 FROM public.stores WHERE id='{uuid.UUID(store_id)}')",
                "local public store fixture")
    counts["sql"] += 1
    status, body, _ = api.request(
        "POST", "/rest/v1/reviews?select=id,user_id,is_hidden", token=a_token,
        payload={"store_id": store_id, "rating": 2,
                 "content": "가격이 아쉬웠지만 솔직한 지역 매장 리뷰입니다."},
        headers={"Prefer": "return=representation"},
    )
    check(status == 201 and isinstance(body, list) and len(body) == 1
          and body[0].get("user_id") == a_id, "A real JWT review create", counts)
    assert isinstance(body, list)
    review_id = str(uuid.UUID(body[0]["id"]))
    review_ids.append(review_id)
    public_path = f"/rest/v1/public_reviews?id=eq.{review_id}&select=id"
    status, body, _ = api.request("GET", public_path)
    check(status == 200 and body == [{"id": review_id}], "anon public baseline", counts)

    report_path = "/rest/v1/review_reports"
    payload = {"review_id": review_id, "reason": "spam", "detail": "광고성 문구 확인 요청"}
    status, _, _ = api.request("POST", report_path, token=b_token, payload=payload,
                               headers={"Prefer": "return=minimal"})
    check(status in {200, 201, 204}, "B reports A review", counts)
    report_rows = rows(api, "review_reports",
                       f"review_id=eq.{review_id}&select=id,review_id,reporter_user_id,reason,detail,status",
                       counts)
    check(len(report_rows) == 1 and report_rows[0]["reporter_user_id"] == b_id
          and report_rows[0]["review_id"] == review_id
          and report_rows[0]["reason"] == "spam"
          and report_rows[0]["detail"] == payload["detail"]
          and report_rows[0]["status"] == "pending", "stored report identity and detail", counts)
    report_id = report_rows[0]["id"]
    for reason, detail in (
        ("spam", "광고성 문구 확인 요청"),
        ("harassment", None),
        ("personal_information", None),
        ("irrelevant", None),
        ("other", "false information"),
    ):
        detail_sql = "NULL" if detail is None else "'false information'"
        probe = subprocess.run(
            [api.docker, "exec", DB_CONTAINER, "psql", "-X", "-qAt",
             "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres",
             "-c", ("BEGIN; UPDATE public.review_reports SET "
                    f"reason='{reason}', detail={detail_sql} "
                    f"WHERE id='{uuid.UUID(report_id)}' RETURNING reason; ROLLBACK;")],
            capture_output=True, text=True, encoding="utf-8", timeout=25, check=False,
        )
        require(probe.returncode == 0 and reason in probe.stdout,
                f"DB accepts mapped reason {reason}")
        counts["sql"] += 1
    invalid = subprocess.run(
        [api.docker, "exec", DB_CONTAINER, "psql", "-X", "-qAt",
         "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=sqlstate",
         "-U", "postgres", "-d", "postgres", "-c",
         ("BEGIN; UPDATE public.review_reports SET reason='false_information' "
          f"WHERE id='{uuid.UUID(report_id)}' RETURNING reason; ROLLBACK;")],
        capture_output=True, text=True, encoding="utf-8", timeout=25, check=False,
    )
    states = re.findall(r"\b[0-9A-Z]{5}\b", invalid.stderr)
    require(invalid.returncode != 0 and "23514" in states,
            f"unmapped DB reason rejection (status={invalid.returncode}, sqlstate={states[:1]})")
    counts["sql"] += 1
    status, body, _ = api.request("GET", public_path)
    check(status == 200 and body == [{"id": review_id}], "report does not auto-hide", counts)
    check(rows(api, "reviews", f"id=eq.{review_id}&select=is_hidden", counts)
          == [{"is_hidden": False}], "report does not mutate review", counts)

    status, _, _ = api.request("POST", report_path, token=b_token, payload=payload)
    check(status >= 400, "duplicate report rejected", counts)
    check(len(rows(api, "review_reports", f"review_id=eq.{review_id}&select=id", counts)) == 1,
          "duplicate leaves one row", counts)
    status, _, _ = api.request("POST", report_path, token=a_token, payload=payload)
    check(status >= 400, "author cannot report own review", counts)
    status, _, _ = api.request("POST", report_path, token=b_token,
                               payload={**payload, "reporter_user_id": c_id})
    check(status >= 400, "B cannot spoof C identity", counts)
    check(len(rows(api, "review_reports", f"review_id=eq.{review_id}&select=id", counts)) == 1,
          "self-report and spoof leave one row", counts)
    status, _, _ = api.request("POST", report_path, payload=payload)
    check(status >= 400, "anon report INSERT rejected", counts)
    for label, token in (("anon", None), ("author", a_token),
                         ("reporter", b_token), ("other", identities[2][1])):
        status, _, _ = api.request("GET", f"{report_path}?select=*", token=token)
        check(status >= 400, f"{label} full report SELECT rejected", counts)
        status, _, _ = api.request("GET", f"{report_path}?select=detail,reporter_user_id&id=eq.{report_id}", token=token)
        check(status >= 400, f"{label} report detail/identity SELECT rejected", counts)
    status, body, _ = api.request("GET", public_path)
    check(status == 200 and body == [{"id": review_id}], "anon public read remains allowed", counts)

    operator = rows(api, "review_reports", f"status=eq.pending&id=eq.{report_id}&select=id,reason,detail,review_id", counts)
    check(len(operator) == 1 and operator[0]["reason"] == "spam"
          and operator[0]["review_id"] == review_id,
          "operator pending queue and linked review", counts)
    check(len(rows(api, "reviews", f"id=eq.{review_id}&select=id,content", counts)) == 1,
          "operator sees linked review", counts)
    moderated_at = datetime.now(timezone.utc).isoformat()
    status, body, _ = api.request(
        "PATCH", f"/rest/v1/reviews?id=eq.{review_id}&select=id,is_hidden",
        service=True,
        payload={"is_hidden": True, "moderation_note": "Local policy test",
                 "moderated_at": moderated_at, "moderated_by": "local_test"},
        headers={"Prefer": "return=representation"},
    )
    check(status == 200 and isinstance(body, list) and len(body) == 1
          and body[0]["is_hidden"] is True, "operator hides review with metadata", counts)
    status, _, _ = api.request(
        "PATCH", f"/rest/v1/review_reports?id=eq.{report_id}", service=True,
        payload={"status": "resolved", "resolution_note": "Local policy test",
                 "resolved_at": moderated_at, "resolved_by": "local_test"},
    )
    check(status in {200, 204}, "operator resolves report", counts)
    check(len(rows(api, "reviews", f"id=eq.{review_id}&select=id,is_hidden", counts)) == 1,
          "hidden source review preserved", counts)
    check(len(rows(api, "review_reports", f"id=eq.{report_id}&select=id,status", counts)) == 1,
          "resolved report preserved", counts)
    for label, token in (("anon", None), ("authenticated", b_token)):
        status, body, _ = api.request("GET", public_path, token=token)
        check(status == 200 and body == [], f"{label} public view hides review", counts)
    status, body, _ = api.request("GET", f"/rest/v1/store_review_stats?store_id=eq.{store_id}&select=review_count")
    check(status == 200 and body == [{"review_count": 0}], "public stats exclude hidden", counts)
    status, body, _ = api.request(
        "PATCH", f"/rest/v1/reviews?id=eq.{review_id}&select=id,is_hidden",
        service=True, payload={"is_hidden": False},
        headers={"Prefer": "return=representation"},
    )
    check(status == 200 and isinstance(body, list) and len(body) == 1
          and body[0]["is_hidden"] is False, "operator can unhide", counts)
    status, body, _ = api.request("GET", public_path)
    check(status == 200 and body == [{"id": review_id}], "unhide restores public review", counts)
    check(len(rows(api, "review_reports", f"id=eq.{report_id}&select=id", counts)) == 1,
          "unhide preserves audit report", counts)


def cleanup(api: LocalApi, users: list[str], store_id: str,
            review_ids: list[str], counts: dict[str, int]) -> None:
    failures: list[str] = []
    def delete(path: str, label: str) -> None:
        try:
            status, _, _ = api.request("DELETE", path, service=True)
        except Exception:
            failures.append(label)
            return
        if status not in {200, 204, 404}:
            failures.append(label)
    for review_id in review_ids:
        delete(f"/rest/v1/review_reports?review_id=eq.{review_id}", "report cleanup")
        delete(f"/rest/v1/reviews?id=eq.{review_id}", "review cleanup")
    store_deleted = False
    try:
        api.sql(f"DELETE FROM public.stores WHERE id='{uuid.UUID(store_id)}';")
        store_deleted = True
    except Exception:
        pass
    for user_id in users:
        delete(f"/auth/v1/admin/users/{user_id}", "Auth cleanup")
    if not store_deleted:
        try:
            api.sql(f"DELETE FROM public.stores WHERE id='{uuid.UUID(store_id)}';")
        except Exception:
            failures.append("store cleanup")
    require(not failures, ", ".join(failures))
    for table, query in (("review_reports", f"review_id=in.({','.join(review_ids)})"),
                         ("reviews", f"id=in.({','.join(review_ids)})"),
                         ("profiles", f"id=in.({','.join(users)})")):
        if table in {"review_reports", "reviews"} and not review_ids:
            continue
        if table == "profiles" and not users:
            continue
        check(rows(api, table, query + "&select=id", counts) == [],
              f"{table} fixtures cleaned", counts)
    sql_boolean(api, f"NOT EXISTS (SELECT 1 FROM public.stores WHERE id='{uuid.UUID(store_id)}')",
                "store fixture cleaned")
    counts["sql"] += 1
    if users:
        values = ",".join(f"'{uuid.UUID(user_id)}'" for user_id in users)
        sql_boolean(api, f"(SELECT count(*) FROM auth.users WHERE id IN ({values})) = 0",
                    "Auth fixtures cleaned")
        counts["sql"] += 1


def main() -> int:
    api = guard()
    counts = {"sql": 0, "rest": 0}
    users: list[str] = []
    review_ids: list[str] = []
    store_id = str(uuid.uuid4())
    failure: Exception | None = None
    try:
        counts["sql"] = sql_contract(api)
        rest_contract(api, users, store_id, review_ids, counts)
    except Exception as error:
        failure = error
    try:
        cleanup(api, users, store_id, review_ids, counts)
    except Exception as error:
        failure = failure or error
    if failure is not None:
        # ContractFailure labels are static; never print response bodies or tokens.
        label = str(failure) if isinstance(failure, AssertionError) else type(failure).__name__
        print(f"REVIEW_REPORT_MODERATION_LOCAL: FAIL ({label})")
        return 1
    print(f"REVIEW_REPORT_MODERATION_SQL: PASS ({counts['sql']} assertions)")
    print(f"REVIEW_REPORT_MODERATION_REST_AUTH_RLS: PASS ({counts['rest']} assertions)")
    print("REVIEW_REPORT_MODERATION_FIXTURE_CLEANUP: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
