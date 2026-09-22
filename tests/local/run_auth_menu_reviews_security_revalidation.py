"""Fresh local-only Auth/Menu/Review security contract runner.

The caller supplies only dedicated loopback Supabase values in this process.
This runner never reads .env and never writes credentials, tokens, or fixture
identifiers to disk.  It is intentionally executable only against a disposable
local stack and leaves its synthetic rows in that disposable stack for the
caller to discard with the project.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
import uuid
from ipaddress import ip_address
from urllib.error import HTTPError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen


REQUIRED = (
    "SUPABASE_LOCAL_API_URL",
    "SUPABASE_LOCAL_ANON_KEY",
    "SUPABASE_LOCAL_SERVICE_KEY",
    "SUPABASE_LOCAL_DB_CONTAINER",
    "SUPABASE_LOCAL_DOCKER",
)


class ContractFailure(AssertionError):
    pass


def require(condition: bool, label: str) -> None:
    if not condition:
        raise ContractFailure(label)


def loopback(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return False
    try:
        return ip_address(parsed.hostname).is_loopback
    except ValueError:
        return parsed.hostname.lower() == "localhost"


class LocalApi:
    def __init__(self) -> None:
        missing = [name for name in REQUIRED if not os.environ.get(name)]
        require(not missing, "missing local-only process configuration")
        self.url = os.environ["SUPABASE_LOCAL_API_URL"].rstrip("/")
        require(loopback(self.url), "refusing non-loopback Supabase URL")
        self.anon = os.environ["SUPABASE_LOCAL_ANON_KEY"]
        self.service = os.environ["SUPABASE_LOCAL_SERVICE_KEY"]
        self.docker = os.environ["SUPABASE_LOCAL_DOCKER"]
        self.container = os.environ["SUPABASE_LOCAL_DB_CONTAINER"]
        self.passed = 0

    def check(self, condition: bool, label: str) -> None:
        require(condition, label)
        self.passed += 1

    def request(self, method: str, path: str, *, token: str | None = None,
                service: bool = False, payload: object | None = None,
                headers: dict[str, str] | None = None):
        key = self.service if service else self.anon
        request_headers = {"apikey": key, "Accept": "application/json"}
        request_headers["Authorization"] = f"Bearer {token or key}"
        if payload is not None:
            request_headers["Content-Type"] = "application/json"
        request_headers.update(headers or {})
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
        request = Request(self.url + path, data=data, headers=request_headers, method=method)
        try:
            with urlopen(request, timeout=20) as response:
                raw = response.read()
                body = json.loads(raw) if raw else None
                return response.status, body, {
                    name: response.headers.get(name)
                    for name in ("Content-Range", "Preference-Applied", "Content-Type")
                }
        except HTTPError as error:
            raw = error.read()
            try:
                body = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                body = None
            return error.code, body, {
                name: error.headers.get(name)
                for name in ("Content-Range", "Preference-Applied", "Content-Type")
            }

    def sql(self, sql: str) -> None:
        result = subprocess.run(
            [self.docker, "exec", "-i", self.container, "psql", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
            input=sql,
            text=True,
            capture_output=True,
            timeout=45,
            check=False,
        )
        # SQL can contain fixture values.  Never print SQL or identifiers; the
        # PostgreSQL SQLSTATE/error class is sufficient to diagnose a failure.
        error_class = "unknown"
        if result.stderr:
            error_class = result.stderr.splitlines()[0][:160]
        require(result.returncode == 0, f"trusted local SQL contract failed ({error_class})")

    def signup(self, label: str, *, anonymous: bool = False) -> tuple[str, str]:
        if anonymous:
            payload: object = {}
        else:
            payload = {
                "email": f"{label}-{uuid.uuid4().hex}@local.invalid",
                "password": f"Local!{uuid.uuid4().hex}",
            }
        status, body, _ = self.request("POST", "/auth/v1/signup", payload=payload)
        self.check(status in {200, 201} and isinstance(body, dict), f"{label}: Auth signup")
        assert isinstance(body, dict)
        user = body.get("user") or {}
        token = body.get("access_token")
        self.check(isinstance(user.get("id"), str) and isinstance(token, str), f"{label}: Auth-issued JWT")
        return user["id"], token  # type: ignore[index]

    def service_insert(self, table: str, payload: dict) -> dict:
        status, body, _ = self.request(
            "POST", f"/rest/v1/{table}", service=True, payload=payload,
            headers={"Prefer": "return=representation"},
        )
        self.check(status in {200, 201} and isinstance(body, list) and len(body) == 1, f"fixture {table} insert")
        assert isinstance(body, list)
        return body[0]

    def service_rows(self, table: str, query: str) -> list[dict]:
        status, body, _ = self.request("GET", f"/rest/v1/{table}?{query}", service=True)
        self.check(status == 200 and isinstance(body, list), f"trusted {table} query")
        assert isinstance(body, list)
        return body

    def snapshot_review(self, review_id: str) -> dict:
        rows = self.service_rows(
            "reviews",
            f"id=eq.{review_id}&select=id,store_id,user_id,rating,content,is_hidden",
        )
        self.check(len(rows) == 1, "trusted review snapshot exists")
        return rows[0]

    def minimal_mutation(self, method: str, path: str, token: str, payload: dict | None = None):
        return self.request(
            method, path, token=token, payload=payload,
            headers={"Prefer": "return=minimal,count=exact"},
        )

    def zero_rows(self, headers: dict[str, str | None]) -> bool:
        value = headers.get("Content-Range")
        return isinstance(value, str) and value.rsplit("/", 1)[-1] == "0"


def create_store(api: LocalApi, label: str, *, public: bool = True) -> dict:
    return api.service_insert("stores", {
        "name": f"Local {label} Burger {uuid.uuid4().hex[:8]}",
        "address": "Yongsan local fixture",
        "latitude": 37.53,
        "longitude": 126.98,
        "verification_status": "verified" if public else "pending",
        "is_active": public,
        "source_type": "manual_review",
        **({"verified_at": "2026-09-22T00:00:00Z"} if public else {}),
    })


def create_profile(api: LocalApi, token: str, user_id: str, nickname: str) -> None:
    status, body, _ = api.request(
        "POST", "/rest/v1/profiles", token=token,
        payload={"id": user_id, "nickname": nickname},
        headers={"Prefer": "return=minimal"},
    )
    code = body.get("code") if isinstance(body, dict) else None
    api.check(
        status in {200, 201, 204} and body is None,
        f"normal user profile create (HTTP {status}, code={code})",
    )
    read_status, rows, _ = api.request(
        "GET", f"/rest/v1/profiles?id=eq.{user_id}&select=id,nickname", token=token,
    )
    api.check(
        read_status == 200 and rows == [{"id": user_id, "nickname": nickname}],
        "normal user profile read after create",
    )


def create_review(api: LocalApi, token: str, store_id: str, rating: int = 4,
                  content: str = "충분히 긴 로컬 보안 계약 리뷰입니다.") -> dict:
    status, body, _ = api.request(
        "POST", "/rest/v1/reviews?select=id,store_id,user_id,rating,content,is_hidden,created_at,updated_at", token=token,
        payload={"store_id": store_id, "rating": rating, "content": content},
        headers={"Prefer": "return=representation"},
    )
    code = body.get("code") if isinstance(body, dict) else None
    api.check(
        status in {200, 201} and isinstance(body, list) and len(body) == 1,
        f"normal user review create (HTTP {status}, code={code})",
    )
    assert isinstance(body, list)
    return body[0]


def install_local_claim_probe(api: LocalApi) -> None:
    api.sql("""
CREATE OR REPLACE VIEW public.local_auth_claim_probe WITH (security_invoker = true) AS
SELECT auth.uid() AS uid, auth.jwt()->>'is_anonymous' AS is_anonymous;
REVOKE ALL ON TABLE public.local_auth_claim_probe FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.local_auth_claim_probe TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
""")
    # The local PostgREST image used by this CLI build does not consume the
    # reload notification for a relation created after startup. Restart only
    # its disposable local container so the probe uses the actual HTTP path.
    rest_container = api.container.replace("supabase_db_", "supabase_rest_", 1)
    result = subprocess.run(
        [api.docker, "restart", rest_container],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    require(result.returncode == 0, "local PostgREST restart for claim probe")
    time.sleep(3)


def claim_tests(api: LocalApi, normal_token: str, normal_id: str, anonymous_token: str, anonymous_id: str) -> None:
    for token, user_id, expected, label in (
        (normal_token, normal_id, "false", "normal Auth JWT reaches auth.jwt"),
        (anonymous_token, anonymous_id, "true", "anonymous Auth JWT reaches auth.jwt"),
    ):
        status, body, _ = api.request("GET", "/rest/v1/local_auth_claim_probe?select=uid,is_anonymous", token=token)
        detail = body.get("code") if isinstance(body, dict) else None
        api.check(
            status == 200 and isinstance(body, list) and len(body) == 1,
            label + f" RPC response (HTTP {status}, code={detail})",
        )
        assert isinstance(body, list) and len(body) == 1
        api.check(body[0].get("uid") == user_id, label + " auth.uid non-null and matches session")
        api.check(body[0].get("is_anonymous") == expected, label + " is_anonymous non-null and exact")


def sql_rls_tests(api: LocalApi, a_id: str, b_id: str, public_store: str, hidden_review: str) -> None:
    # This SQL suite intentionally uses the same JSON setting PostgREST supplies.
    # Actual Auth JWT claim propagation is separately verified through the RPC above.
    api.sql(f"""
BEGIN;
CREATE OR REPLACE FUNCTION pg_temp.assert_true(value boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion failed: %', label; END IF; END; $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{{"sub":"{a_id}","role":"authenticated","is_anonymous":false}}', true);
SELECT pg_temp.assert_true(auth.uid() = '{a_id}'::uuid, 'auth.uid positive control');
SELECT pg_temp.assert_true((auth.jwt()->>'is_anonymous') = 'false', 'regular JWT claim positive control');
SELECT pg_temp.assert_true(burger_map_private.can_contribute(), 'normal profile may contribute');
SELECT pg_temp.assert_true(EXISTS (SELECT 1 FROM public.reviews WHERE id = '{hidden_review}'::uuid), 'owner reads own hidden row');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{{"sub":"{b_id}","role":"authenticated","is_anonymous":false}}', true);
DO $$ DECLARE changed_rows integer; BEGIN
  UPDATE public.reviews SET rating = 1 WHERE id = '{hidden_review}'::uuid;
  GET DIAGNOSTICS changed_rows = ROW_COUNT;
  PERFORM pg_temp.assert_true(changed_rows = 0, 'other owner update is zero rows');
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{{"sub":"{a_id}","role":"authenticated","is_anonymous":true}}', true);
SELECT pg_temp.assert_true(auth.jwt()->>'is_anonymous' = 'true', 'anonymous claim is present');
SELECT pg_temp.assert_true(burger_map_private.can_contribute() IS FALSE, 'anonymous cannot contribute');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{{"role":"anon"}}', true);
SELECT pg_temp.assert_true(NOT has_function_privilege('anon', (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'burger_map_private' AND p.proname = 'can_contribute' AND p.pronargs = 0), 'EXECUTE'), 'anon helper execute denied');
SELECT pg_temp.assert_true(NOT has_schema_privilege('anon', 'burger_map_private', 'USAGE'), 'anon private schema usage denied');
ROLLBACK;
""")
    api.passed += 10


def crud_and_forging_tests(api: LocalApi, a: tuple[str, str], b: tuple[str, str], public: dict) -> tuple[dict, dict]:
    a_id, a_token = a
    b_id, b_token = b
    a_review = create_review(api, a_token, public["id"], 4)
    status, rows, _ = api.request("GET", f"/rest/v1/reviews?id=eq.{a_review['id']}&select=id,rating,content", token=a_token)
    api.check(status == 200 and isinstance(rows, list) and len(rows) == 1, "owner review read")
    status, rows, _ = api.request("GET", f"/rest/v1/public_reviews?id=eq.{a_review['id']}&select=id,rating", token=b_token)
    api.check(status == 200 and isinstance(rows, list) and len(rows) == 1, "other user reads public review")
    status, _, _ = api.minimal_mutation("PATCH", f"/rest/v1/reviews?id=eq.{a_review['id']}", a_token, {"rating": 5, "content": "수정 후에도 충분히 긴 정상 리뷰 본문입니다."})
    api.check(status == 204, "owner review rating/content update")
    api.check(api.snapshot_review(a_review["id"])["rating"] == 5, "owner update persisted")
    before = api.snapshot_review(a_review["id"])
    status, _, headers = api.minimal_mutation("PATCH", f"/rest/v1/reviews?id=eq.{a_review['id']}", b_token, {"rating": 1})
    api.check(status == 204 and api.zero_rows(headers), "other user PATCH is actual zero rows")
    api.check(api.snapshot_review(a_review["id"]) == before, "other user PATCH preserves every protected value")
    status, _, headers = api.minimal_mutation("DELETE", f"/rest/v1/reviews?id=eq.{a_review['id']}", b_token)
    api.check(status == 204 and api.zero_rows(headers), "other user DELETE is actual zero rows")
    api.check(api.snapshot_review(a_review["id"]) == before, "other user DELETE preserves row")

    forging_store = create_store(api, "forging")
    status, _, _ = api.request("POST", "/rest/v1/reviews", token=a_token, payload={
        "store_id": forging_store["id"], "user_id": b_id, "rating": 4,
        "content": "다른 사용자의 식별자를 넣은 위조 리뷰입니다.",
    })
    api.check(status in {400, 401, 403}, "review user_id forging rejected")
    api.check(not api.service_rows("reviews", f"store_id=eq.{forging_store['id']}&select=id"), "forged review absent")
    for field, value in (("user_id", b_id), ("store_id", forging_store["id"]), ("created_at", "2020-01-01T00:00:00Z"), ("is_hidden", True), ("moderation_note", "operator"), ("moderated_at", "2026-09-22T00:00:00Z"), ("moderated_by", "operator")):
        status, _, _ = api.minimal_mutation("PATCH", f"/rest/v1/reviews?id=eq.{a_review['id']}", a_token, {field: value})
        api.check(status in {400, 401, 403}, f"review operational column {field} rejected")
        api.check(api.snapshot_review(a_review["id"]) == before, f"review operational column {field} invariant")

    # The normal delete path is deliberately checked after the blocked attacks.
    status, _, headers = api.minimal_mutation("DELETE", f"/rest/v1/reviews?id=eq.{a_review['id']}", a_token)
    api.check(status == 204 and not api.zero_rows(headers), "owner review delete")
    api.check(not api.service_rows("reviews", f"id=eq.{a_review['id']}&select=id"), "owner delete removed review")

    b_review = create_review(api, b_token, create_store(api, "b-review")["id"], 3)
    return a_review, b_review


def profile_and_boundary_tests(api: LocalApi, a: tuple[str, str], b: tuple[str, str]) -> None:
    a_id, a_token = a
    b_id, b_token = b
    status, _, _ = api.request("GET", f"/rest/v1/profiles?id=eq.{a_id}&select=is_suspended", token=a_token)
    api.check(status in {400, 401, 403}, "profile is_suspended direct SELECT denied")
    status, _, _ = api.minimal_mutation("DELETE", f"/rest/v1/profiles?id=eq.{a_id}", a_token)
    api.check(status in {400, 401, 403}, "profile direct DELETE denied")
    outsider_id, outsider_token = api.signup("profile-forging")
    status, _, _ = api.request("POST", "/rest/v1/profiles", token=a_token, payload={"id": outsider_id, "nickname": "outsider"})
    api.check(status in {400, 401, 403}, "profile id forging rejected")
    api.check(not api.service_rows("profiles", f"id=eq.{outsider_id}&select=id"), "forged profile absent")
    status, _, _ = api.request(
        "POST", "/rest/v1/profiles", token=outsider_token,
        payload={"id": outsider_id, "nickname": "outsider", "is_suspended": True},
    )
    api.check(status in {400, 401, 403}, "profile is_suspended insert override rejected")
    api.check(not api.service_rows("profiles", f"id=eq.{outsider_id}&select=id"), "suspension-injected profile absent")
    status, _, _ = api.minimal_mutation("PATCH", f"/rest/v1/profiles?id=eq.{a_id}", a_token, {"is_suspended": True})
    api.check(status in {400, 401, 403}, "profile suspension mutation rejected")
    api.check(api.service_rows("profiles", f"id=eq.{a_id}&select=is_suspended")[0]["is_suspended"] is False, "profile suspension invariant")
    for nickname, accepted, label in (("a", False, "nickname one character"), ("가나", True, "nickname lower boundary"), ("a" * 20, True, "nickname upper boundary"), ("a" * 21, False, "nickname over boundary")):
        status, _, _ = api.request("PATCH", f"/rest/v1/profiles?id=eq.{outsider_id}", token=outsider_token, payload={"nickname": nickname}, headers={"Prefer": "return=minimal"}) if api.service_rows("profiles", f"id=eq.{outsider_id}&select=id") else api.request("POST", "/rest/v1/profiles", token=outsider_token, payload={"id": outsider_id, "nickname": nickname}, headers={"Prefer": "return=minimal"})
        api.check((status in {200, 201, 204}) == accepted, label)
    status, _, _ = api.minimal_mutation("PATCH", f"/rest/v1/profiles?id=eq.{outsider_id}", outsider_token, {"nickname": "admin"})
    api.check(status in {400, 401, 403}, "reserved nickname rejected")
    status, _, _ = api.minimal_mutation("PATCH", f"/rest/v1/profiles?id=eq.{outsider_id}", outsider_token, {"nickname": "name!"})
    api.check(status in {400, 401, 403}, "disallowed nickname character rejected")
    # Existing profile must not be alterable by another account.
    status, _, headers = api.minimal_mutation("PATCH", f"/rest/v1/profiles?id=eq.{a_id}", b_token, {"nickname": "other"})
    api.check(status == 204 and api.zero_rows(headers), "other user profile PATCH is zero rows")

    store = create_store(api, "content-boundary")
    for content, accepted, label in ((" " * 10, False, "whitespace content"), ("가" * 9, False, "content 9"), ("가" * 10, True, "content 10"), ("가" * 2000, True, "content 2000"), ("가" * 2001, False, "content 2001"), ("한글과 😀 emoji를 포함한 충분히 긴 리뷰입니다.", True, "unicode content")):
        status, body, _ = api.request("POST", "/rest/v1/reviews?select=id", token=a_token, payload={"store_id": store["id"], "rating": 4, "content": content}, headers={"Prefer": "return=representation"})
        api.check((status in {200, 201}) == accepted, label)
        if accepted:
            assert isinstance(body, list) and body
            api.minimal_mutation("DELETE", f"/rest/v1/reviews?id=eq.{body[0]['id']}", a_token)
    for rating, accepted in ((None, False), (0, False), (1, True), (5, True), (6, False)):
        status, body, _ = api.request("POST", "/rest/v1/reviews?select=id", token=a_token, payload={"store_id": store["id"], "rating": rating, "content": "별점 경계 확인을 위한 충분히 긴 본문입니다."}, headers={"Prefer": "return=representation"})
        api.check((status in {200, 201}) == accepted, f"rating {rating}")
        if accepted:
            assert isinstance(body, list) and body
            api.minimal_mutation("DELETE", f"/rest/v1/reviews?id=eq.{body[0]['id']}", a_token)


def report_and_visibility_tests(api: LocalApi, a: tuple[str, str], b: tuple[str, str], c: tuple[str, str], d: tuple[str, str], b_review: dict) -> None:
    a_id, a_token = a
    b_id, b_token = b
    _, c_token = c
    _, d_token = d
    target = b_review["id"]
    # A may report B's public review.  No client read/return path is granted.
    status, _, _ = api.minimal_mutation("POST", "/rest/v1/review_reports", a_token, {"review_id": target, "reason": "spam"})
    api.check(status in {200, 201, 204}, "valid report insert")
    reports = api.service_rows("review_reports", f"review_id=eq.{target}&reporter_user_id=eq.{a_id}&select=id,review_id,reporter_user_id,status")
    api.check(len(reports) == 1 and reports[0]["status"] == "pending", "valid report trusted row")
    report = reports[0]
    for method, path in (("GET", "/rest/v1/review_reports?select=id"), ("HEAD", "/rest/v1/review_reports?select=id"), ("PATCH", f"/rest/v1/review_reports?id=eq.{report['id']}"), ("DELETE", f"/rest/v1/review_reports?id=eq.{report['id']}")):
        status, _, _ = api.request(method, path, token=a_token, payload={"status": "resolved"} if method == "PATCH" else None)
        api.check(status in {400, 401, 403}, f"report client {method} denied")
    baseline = api.service_rows("review_reports", f"id=eq.{report['id']}&select=status,resolution_note,resolved_at,resolved_by,reporter_user_id")[0]
    for field, value in (("status", "resolved"), ("resolution_note", "no"), ("resolved_at", "2026-09-22T00:00:00Z"), ("resolved_by", "operator"), ("reporter_user_id", b_id)):
        status, _, _ = api.request("POST", "/rest/v1/review_reports", token=b_token, payload={"review_id": target, "reason": "spam", field: value})
        api.check(status in {400, 401, 403}, f"report operational/identity field {field} rejected")
    api.check(api.service_rows("review_reports", f"id=eq.{report['id']}&select=status,resolution_note,resolved_at,resolved_by,reporter_user_id")[0] == baseline, "report system columns invariant")
    hidden_store = create_store(api, "hidden-report")
    hidden_target = api.service_insert("reviews", {"store_id": hidden_store["id"], "user_id": b_id, "rating": 4, "content": "신고 대상 숨김 리뷰의 충분히 긴 로컬 본문입니다.", "is_hidden": True, "moderation_note": "fixture", "moderated_at": "2026-09-22T00:00:00Z", "moderated_by": "fixture"})
    private_store = create_store(api, "private-report", public=False)
    private_target = api.service_insert("reviews", {"store_id": private_store["id"], "user_id": b_id, "rating": 4, "content": "비공개 매장 신고 대상의 충분히 긴 로컬 본문입니다."})
    for token, payload, label in (
        (a_token, {"review_id": target, "reason": "spam"}, "duplicate report"),
        (b_token, {"review_id": target, "reason": "spam"}, "self report"),
        (d_token, {"review_id": target, "reason": "spam"}, "anonymous report"),
        (c_token, {"review_id": target, "reason": "spam"}, "suspended report"),
        (a_token, {"review_id": hidden_target["id"], "reason": "spam"}, "hidden report target"),
        (a_token, {"review_id": private_target["id"], "reason": "spam"}, "non-public report target"),
        (a_token, {"review_id": target, "reporter_user_id": b_id, "reason": "harassment"}, "reporter identity forging"),
        (a_token, {"review_id": str(uuid.uuid4()), "reason": "spam"}, "nonexistent report target"),
    ):
        status, _, _ = api.request("POST", "/rest/v1/review_reports", token=token, payload=payload)
        api.check(status not in {200, 201, 204}, label + " rejected")


def duplicate_and_aggregate_tests(api: LocalApi, a: tuple[str, str], b: tuple[str, str]) -> None:
    _, a_token = a
    _, b_token = b
    duplicate_store = create_store(api, "duplicate")
    outcomes: list[int] = []
    def post_duplicate() -> None:
        status, _, _ = api.request("POST", "/rest/v1/reviews", token=a_token, payload={"store_id": duplicate_store["id"], "rating": 4, "content": "동시 중복 방지를 확인하는 충분히 긴 리뷰입니다."})
        outcomes.append(status)
    threads = [threading.Thread(target=post_duplicate), threading.Thread(target=post_duplicate)]
    [thread.start() for thread in threads]
    [thread.join() for thread in threads]
    api.check(sum(status in {200, 201} for status in outcomes) == 1, "duplicate concurrent insert has one winner")
    api.check(len(api.service_rows("reviews", f"store_id=eq.{duplicate_store['id']}&select=id")) == 1, "duplicate unique constraint persisted once")

    store = create_store(api, "aggregate")
    a_review = create_review(api, a_token, store["id"], 5)
    def stats(expected_count, expected_avg, label):
        rows = api.service_rows("store_review_stats", f"store_id=eq.{store['id']}&select=review_count,average_rating")
        api.check(len(rows) == 1 and rows[0]["review_count"] == expected_count and rows[0]["average_rating"] == expected_avg, label)
    stats(1, 5.0, "aggregate one review")
    b_review = create_review(api, b_token, store["id"], 3)
    stats(2, 4.0, "aggregate two reviews")
    api.minimal_mutation("PATCH", f"/rest/v1/reviews?id=eq.{a_review['id']}", a_token, {"rating": 1})
    stats(2, 2.0, "aggregate owner rating update")
    api.request("PATCH", f"/rest/v1/reviews?id=eq.{a_review['id']}", service=True, payload={"is_hidden": True, "moderation_note": "fixture hide", "moderated_at": "2026-09-22T00:00:00Z", "moderated_by": "fixture"})
    stats(1, 3.0, "aggregate hidden excluded")
    api.minimal_mutation("DELETE", f"/rest/v1/reviews?id=eq.{b_review['id']}", b_token)
    stats(0, None, "aggregate delete recalculates")
    api.request("PATCH", f"/rest/v1/stores?id=eq.{store['id']}", service=True, payload={"is_active": False})
    api.check(not api.service_rows("store_review_stats", f"store_id=eq.{store['id']}&select=store_id"), "non-public store hidden from stats")


def cascade_and_catalog_tests(api: LocalApi, a: tuple[str, str], b: tuple[str, str]) -> None:
    z_id, z_token = api.signup("cascade-user")
    create_profile(api, z_token, z_id, "cascade_user")
    store = create_store(api, "cascade")
    api.service_insert("menus", {"store_id": store["id"], "name": "cascade fixture menu", "is_active": True})
    review = create_review(api, z_token, store["id"], 4)
    # B reports Z's public review, then an auth.users delete cascades all Z-owned rows.
    _, b_token = b
    status, _, _ = api.minimal_mutation("POST", "/rest/v1/review_reports", b_token, {"review_id": review["id"], "reason": "spam"})
    api.check(status in {200, 201, 204}, "cascade fixture report")
    direct_store = create_store(api, "review-delete-cascade")
    direct_review = create_review(api, z_token, direct_store["id"], 4)
    status, _, _ = api.minimal_mutation("POST", "/rest/v1/review_reports", b_token, {"review_id": direct_review["id"], "reason": "spam"})
    api.check(status in {200, 201, 204}, "review-delete cascade fixture report")
    status, _, headers = api.minimal_mutation("DELETE", f"/rest/v1/reviews?id=eq.{direct_review['id']}", z_token)
    api.check(status == 204 and not api.zero_rows(headers), "owner direct review delete")
    api.check(not api.service_rows("review_reports", f"review_id=eq.{direct_review['id']}&select=id"), "direct review delete cascades reports")
    api.sql(f"""
DO $$ BEGIN
  IF (SELECT count(*) FROM public.profiles WHERE id = '{z_id}'::uuid) <> 1 THEN RAISE EXCEPTION 'profile fixture missing'; END IF;
  IF (SELECT count(*) FROM public.reviews WHERE id = '{review['id']}'::uuid) <> 1 THEN RAISE EXCEPTION 'review fixture missing'; END IF;
  IF (SELECT count(*) FROM public.review_reports WHERE review_id = '{review['id']}'::uuid) <> 1 THEN RAISE EXCEPTION 'report fixture missing'; END IF;
  DELETE FROM auth.users WHERE id = '{z_id}'::uuid;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = '{z_id}'::uuid) OR EXISTS (SELECT 1 FROM public.reviews WHERE id = '{review['id']}'::uuid) OR EXISTS (SELECT 1 FROM public.review_reports WHERE review_id = '{review['id']}'::uuid) THEN RAISE EXCEPTION 'auth cascade failed'; END IF;
  BEGIN DELETE FROM public.stores WHERE id = '{store['id']}'::uuid; RAISE EXCEPTION 'store RESTRICT unexpectedly allowed';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
""")
    api.passed += 5
    status, _, _ = api.request("POST", "/rest/v1/reviews", token=z_token, payload={"store_id": store["id"], "rating": 4, "content": "삭제된 계정의 토큰은 재기여하면 안 되는 충분한 길이의 본문입니다."})
    api.check(status in {400, 401, 403}, "deleted account JWT cannot recreate review")
    api.sql("""
DO $$ DECLARE invoker boolean; BEGIN
  SELECT (reloptions @> ARRAY['security_invoker=true']) INTO invoker FROM pg_class WHERE oid = 'public.public_reviews'::regclass;
  IF invoker IS DISTINCT FROM true THEN RAISE EXCEPTION 'public_reviews not invoker'; END IF;
  SELECT (reloptions @> ARRAY['security_invoker=true']) INTO invoker FROM pg_class WHERE oid = 'public.store_review_stats'::regclass;
  IF invoker IS DISTINCT FROM true THEN RAISE EXCEPTION 'store_review_stats not invoker'; END IF;
  IF has_function_privilege('public', 'burger_map_private.can_contribute()', 'EXECUTE') THEN RAISE EXCEPTION 'PUBLIC helper execute'; END IF;
  IF has_function_privilege('anon', 'burger_map_private.can_contribute()', 'EXECUTE') THEN RAISE EXCEPTION 'anon helper execute'; END IF;
  IF NOT has_function_privilege('authenticated', 'burger_map_private.can_contribute()', 'EXECUTE') THEN RAISE EXCEPTION 'authenticated helper execute missing'; END IF;
  IF (SELECT prosecdef AND proconfig @> ARRAY['search_path=pg_catalog'] FROM pg_proc WHERE oid='burger_map_private.can_contribute()'::regprocedure) IS DISTINCT FROM true THEN RAISE EXCEPTION 'helper security definition'; END IF;
END $$;
""")
    api.passed += 6
    status, _, _ = api.request("GET", "/rest/v1/burger_map_private.can_contribute")
    api.check(status in {404, 400}, "private schema is not locally exposed through Data API")


def main() -> int:
    api = LocalApi()
    a = api.signup("security-a")
    b = api.signup("security-b")
    c = api.signup("security-c")
    d = api.signup("security-anonymous", anonymous=True)
    install_local_claim_probe(api)
    claim_tests(api, a[1], a[0], d[1], d[0])
    create_profile(api, a[1], a[0], "security_a")
    create_profile(api, b[1], b[0], "security_b")
    api.service_insert("profiles", {"id": c[0], "nickname": "security_c", "is_suspended": True})
    public = create_store(api, "public")
    hidden_store = create_store(api, "hidden-owner")
    hidden = api.service_insert("reviews", {"store_id": hidden_store["id"], "user_id": a[0], "rating": 4, "content": "숨김 행 권한 검증에 사용할 충분히 긴 로컬 리뷰입니다.", "is_hidden": True, "moderation_note": "fixture", "moderated_at": "2026-09-22T00:00:00Z", "moderated_by": "fixture"})
    sql_rls_tests(api, a[0], b[0], public["id"], hidden["id"])
    _, b_review = crud_and_forging_tests(api, a, b, public)
    profile_and_boundary_tests(api, a, b)
    report_and_visibility_tests(api, a, b, c, d, b_review)
    duplicate_and_aggregate_tests(api, a, b)
    cascade_and_catalog_tests(api, a, b)
    print(f"AUTH_MENU_REVIEW_SQL_RLS_REST: PASS ({api.passed} assertions)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        # Never include response bodies, headers, identifiers, or environment values.
        print(f"AUTH_MENU_REVIEW_SQL_RLS_REST: FAIL ({type(error).__name__}: {error})")
        raise SystemExit(1)
