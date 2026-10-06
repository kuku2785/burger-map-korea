"""Real Auth JWT -> Edge Function -> Auth hard delete, dedicated local stack only.

Credentials are supplied in process environment; never reads application .env.
Output contains assertion labels/counts/statuses only, never fixture identities.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import subprocess
import time
import uuid

from run_auth_menu_reviews_security_revalidation import LocalApi, require

PROJECT = "account_delete_local_20261005_01"
URL = "http://127.0.0.1:57321"


def main():
    api = LocalApi()
    require(api.url == URL and api.container == "supabase_db_" + PROJECT,
            "refusing anything except dedicated deletion validation stack")
    result = subprocess.run([api.docker, "inspect", "--format", "{{.State.Running}}", api.container],
                            capture_output=True, text=True, check=True)
    require(result.stdout.strip() == "true", "dedicated database must be running")
    users = []
    store_id = str(uuid.uuid4())
    results = {}

    def check(ok, label):
        api.check(ok, label)
        results[label] = "PASS"
        print(label + ": PASS", flush=True)

    def count(table, where="true"):
        r = subprocess.run([api.docker, "exec", "-i", api.container, "psql", "-At", "-v", "ON_ERROR_STOP=1",
                            "-U", "postgres", "-d", "postgres"],
                           input=f"select count(*) from {table} where {where};", text=True,
                           capture_output=True, check=False)
        require(r.returncode == 0, "local count query failed")
        return int(r.stdout.strip())

    def invoke(token, body=None, query="", headers=None):
        return api.request("POST", "/functions/v1/delete-account" + query, token=token,
                           payload={"confirmation": "DELETE"} if body is None else body,
                           headers=headers)[0]

    try:
        for table in ["auth.users", "public.profiles", "public.reviews", "public.review_reports", "public.stores"]:
            require(count(table) == 0, "dedicated fixture database must start empty")
        check(invoke(None, headers={"Authorization": ""}) == 401, "no_authorization_rejected")
        check(invoke("invalid") == 401, "invalid_jwt_rejected")
        for label in ["A", "B", "C", "D"]:
            users.append(api.signup("delete" + label))
        (a, at), (b, bt), (c, ct), (d, dt) = users
        api.sql(f"""INSERT INTO public.stores(id,name,address,latitude,longitude,verification_status,is_active,source_type,verified_at)
        VALUES('{store_id}','Local deletion fixture','Local fixture',37.53,126.98,'verified',true,'manual_review',now());""")
        for label, (uid, token) in zip(["A", "B", "C"], users[:3]):
            status, _, _ = api.request("POST", "/rest/v1/profiles", token=token,
                                      payload={"id": uid, "nickname": "DeleteTest" + label})
            check(status == 201, "profile_" + label + "_created_with_jwt")
        reviews = []
        for label, (_, token) in zip(["A", "B", "C"], users[:3]):
            status, body, _ = api.request("POST", "/rest/v1/reviews?select=id", token=token,
                payload={"store_id": store_id, "rating": 4, "content": "Local deletion test review"},
                headers={"Prefer": "return=representation"})
            check(status == 201 and len(body) == 1, "review_" + label + "_created_with_jwt")
            reviews.append(body[0]["id"])
        ar, br, cr = reviews
        for label, token, review in [("A_on_B", at, br), ("B_on_A", bt, ar), ("C_on_B", ct, br)]:
            status, _, _ = api.request("POST", "/rest/v1/review_reports", token=token,
                                     payload={"review_id": review, "reason": "spam"})
            check(status == 201, "report_" + label + "_created_with_jwt")
        before_b = api.service_rows("profiles", f"id=eq.{b}&select=*")
        before_br = api.service_rows("reviews", f"id=eq.{br}&select=*")
        before_report = api.service_rows("review_reports", f"reporter_user_id=eq.{c}&select=*")
        check(invoke(at, {"confirmation": "DELETE", "user_id": b}) == 400,
              "cross_user_body_rejected")
        check(invoke(at, query=f"?user_id={b}") == 400, "cross_user_query_rejected")
        check(count("auth.users") == 4, "cross_user_attempts_delete_nobody")

        # Expired, correctly signed LOCAL token: keeps issuer/session/sub claims.
        secret = os.environ["SUPABASE_LOCAL_JWT_SECRET"]
        decode = lambda x: json.loads(base64.urlsafe_b64decode(x + "=" * (-len(x) % 4)))
        encode = lambda x: base64.urlsafe_b64encode(json.dumps(x, separators=(",", ":")).encode()).rstrip(b"=")
        claims = decode(at.split(".")[1])
        claims["exp"] = int(time.time()) - 120
        unsigned = encode({"alg": "HS256", "typ": "JWT"}) + b"." + encode(claims)
        expired = (unsigned + b"." + base64.urlsafe_b64encode(hmac.new(secret.encode(), unsigned, hashlib.sha256).digest()).rstrip(b"=")).decode()
        check(invoke(expired) == 401, "expired_signed_jwt_rejected")
        status, _, _ = api.request("POST", "/auth/v1/logout?scope=global", token=ct)
        check(status == 204, "fixture_session_revoked")
        check(invoke(ct) == 401, "revoked_session_rejected")
        check(count("auth.users", f"id='{c}'") == 1, "revoked_session_user_preserved")

        # A simulated FK-trigger failure must roll back Auth and all cascades.
        api.sql("""CREATE FUNCTION public.local_delete_failure() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'isolated forced cascade failure'; END; $$;
        CREATE TRIGGER local_delete_failure BEFORE DELETE ON public.profiles
        FOR EACH ROW EXECUTE FUNCTION public.local_delete_failure();""")
        try:
            check(invoke(at) == 503, "cascade_failure_returns_safe_503")
            check(count("auth.users", f"id='{a}'") == 1 and count("public.profiles", f"id='{a}'") == 1
                  and count("public.reviews") == 3 and count("public.review_reports") == 3,
                  "cascade_failure_rolls_back_auth_and_app_rows")
            check(api.request("GET", "/auth/v1/user", token=at)[0] == 200,
                  "cascade_failure_preserves_session")
        finally:
            api.sql("DROP TRIGGER IF EXISTS local_delete_failure ON public.profiles; DROP FUNCTION IF EXISTS public.local_delete_failure();")

        api.sql(f"UPDATE public.profiles SET is_suspended=true WHERE id='{a}';")
        check(invoke(at) == 204, "suspended_own_account_delete")
        check(count("auth.users", f"id='{a}'") == 0, "auth_A_removed")
        check(count("public.profiles", f"id='{a}'") == 0, "profile_A_removed")
        check(count("public.reviews", f"user_id='{a}'") == 0, "reviews_A_removed")
        check(count("public.review_reports", f"reporter_user_id='{a}' OR review_id='{ar}'") == 0,
              "reports_by_A_and_on_A_removed")
        check(api.service_rows("profiles", f"id=eq.{b}&select=*") == before_b
              and api.service_rows("reviews", f"id=eq.{br}&select=*") == before_br
              and api.service_rows("review_reports", f"reporter_user_id=eq.{c}&select=*") == before_report
              and api.request("GET", "/auth/v1/user", token=bt)[0] == 200,
              "B_account_profile_review_and_unrelated_report_unchanged")
        check(count("public.stores", f"id='{store_id}'") == 1, "store_preserved")
        check(count("auth.sessions", f"user_id='{a}'") == 0
              and count("auth.identities", f"user_id='{a}'") == 0, "auth_sessions_and_identities_removed")
        check(invoke(at) == 401, "repeat_delete_rejected_without_mutation")
        status = api.request("GET", "/auth/v1/user", token=at)[0]
        check(status in (401, 403), "deleted_user_get_user_rejected")
        results["old_jwt_auth_user_status"] = status
        for table, query in [("profiles", f"id=eq.{a}&select=id,nickname"),
                             ("reviews", f"user_id=eq.{a}&select=id")]:
            status, body, _ = api.request("GET", f"/rest/v1/{table}?{query}", token=at)
            check(status == 200 and body == [], "old_jwt_" + table + "_own_rows_empty")
        status, body, _ = api.request("GET", f"/rest/v1/reviews?id=eq.{br}&select=id", token=at)
        check(status == 200 and len(body) == 1, "old_jwt_public_read_still_allowed")
        for label, table, payload, expected in [
            ("profile", "profiles", {"id": a, "nickname": "RetryTest"}, 409),
            ("review", "reviews", {"store_id": store_id, "rating": 4}, 403),
            ("report", "review_reports", {"review_id": br, "reason": "spam"}, 403)]:
            status = api.request("POST", f"/rest/v1/{table}", token=at, payload=payload)[0]
            check(status == expected, "old_jwt_" + label + "_write_blocked")
            results["old_jwt_" + label + "_write_status"] = status
        check(invoke(dt) == 204, "profileless_account_delete")
    finally:
        # All identifiers originate in this invocation, after the exact local guard.
        api.sql("DROP TRIGGER IF EXISTS local_delete_failure ON public.profiles; DROP FUNCTION IF EXISTS public.local_delete_failure();")
        for uid, _ in users:
            status = api.request("DELETE", "/auth/v1/admin/users/" + uid, service=True,
                                 payload={"should_soft_delete": False})[0]
            require(status in (200, 204, 404), "local fixture cleanup failed")
        api.sql(f"DELETE FROM public.stores WHERE id='{store_id}';")
        for table in ["auth.users", "public.profiles", "public.reviews", "public.review_reports", "public.stores"]:
            check(count(table) == 0, "cleanup_" + table + "_zero")
    results["assertions"] = api.passed
    print(json.dumps(results, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Assertion labels are safe; unknown errors may carry sensitive payloads.
        from run_auth_menu_reviews_security_revalidation import ContractFailure
        print("FAIL: " + (str(error) if isinstance(error, ContractFailure) else type(error).__name__))
        raise SystemExit(1)
