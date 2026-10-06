# Account Deletion Backend — 2026-10-05

**ACCOUNT_DELETION_BACKEND_LOCAL_PASS / IMPLEMENTED_LOCAL_NOT_DEPLOYED**

## A. Repository

`nearby-store-sort`, HEAD `f152a65121f7488df89cd3324ca6401170b7a105`.
Fresh `git ls-remote origin refs/heads/nearby-store-sort` matched HEAD. Existing dirty work preserved.

## B. Actual FK / Cascade Contract

Re-read all four repository migrations, then queried `pg_constraint` in the dedicated
local database and production through read-only Supabase MCP. Production project
was matched to the configured Supabase URL without exposing credential values.
The following application FKs match in migrations, local and production:

| Parent | Child | Column | ON DELETE |
|---|---|---|---|
| auth.users | public.profiles | id | CASCADE |
| public.profiles | public.reviews | user_id | CASCADE |
| public.profiles | public.review_reports | reporter_user_id | CASCADE |
| public.reviews | public.review_reports | review_id | CASCADE |
| public.stores | public.reviews | store_id | RESTRICT |
| public.stores | public.menus | store_id | RESTRICT |
| public.stores | burger_map_private.menu_evidence | store_id | RESTRICT |
| public.menus | burger_map_private.menu_evidence | (store_id, menu_id) → (store_id, id) | RESTRICT |

No application FK uses SET NULL/NO ACTION. Public views are not separately stored
user-owned rows. Public/private user/owner column inventory found reviews.user_id,
review_reports.reporter_user_id and the public_reviews view; profiles.id is covered above.
Production profiles/reviews/reports RLS definitions were also read and match the
ownership/profile-presence behavior tested locally. No production user rows were read.

Production Auth internals directly referencing auth.users:

| Parent | Child | Column | ON DELETE | Local parity |
|---|---|---|---|---|
| auth.users | auth.identities | user_id | CASCADE | Yes |
| auth.users | auth.sessions | user_id | CASCADE | Yes |
| auth.users | auth.mfa_factors | user_id | CASCADE | Yes |
| auth.users | auth.one_time_tokens | user_id | CASCADE | Yes |
| auth.users | auth.oauth_authorizations | user_id | CASCADE | Yes |
| auth.users | auth.oauth_consents | user_id | CASCADE | Yes |
| auth.users | auth.webauthn_credentials | user_id | CASCADE | Yes |
| auth.users | auth.webauthn_challenges | user_id | CASCADE | Yes |
| auth.users | auth.mfa_recovery_code_sets | user_id | CASCADE | Absent locally |
| auth.users | auth.scim_users | user_id | SET NULL | Absent locally |

Local auth.refresh_tokens.session_id and auth.mfa_amr_claims.session_id cascade from
auth.sessions; auth.mfa_challenges.factor_id cascades from auth.mfa_factors. This is
not a claim that all hosted Auth internals/versions or external logs match local.

Deleting A removes A's profile, reviews and reports, plus **other users' reports on
A's reviews**. Review moderation fields and report resolution fields disappear with
their rows. B's unrelated profile/review and C's report on B remain unchanged.
Stores/menus/menu_evidence are not user-owned deletion targets. A mandatory abuse
evidence-retention policy would conflict with these cascades and needs a separate
explicit decision/design; this task introduces no retention exception or schema change.
Auth audit logs are separate: after fixture cleanup, the local database still had
25 audit events (including the initial failed test setup run). The dedicated volume
was then destroyed. Hosted audit/log/backup retention and SCIM residual rows must be
described accurately; do not promise immediate erasure of every provider record.

## C–E. Gap, architecture and security

Before: logout only; no account deletion server endpoint. Now: server implementation
and isolated E2E exist; production has no deployed function, Flutter deletion UI or
external deletion-request URL.

Native Flutter later → POST function with JWT + explicit confirmation → online Auth
GET user validation → verified user ID only → Admin hard delete → database cascades.
No SDK dependency, database credential, migration, extra SQL RPC or client admin key
is needed. Built-in server environment supplies URL/service key. Query parameters and
extra body fields are rejected. No user ID is accepted from a client. Anonymous,
invalid, expired and revoked credentials are rejected; profile-less and app-suspended
users can delete themselves. The handler has no logging calls and generic errors.

Fresh Google reauthentication is not required by the Admin API; this phase deliberately
does not implement a recent-login policy. Online live-user/session validation and exact
confirmation are required. A future UI must warn clearly and confirm destructive intent;
an explicit recent-auth policy can be evaluated separately. Refreshing a JWT is not fresh
Google authentication. Auth-level banned-user behavior is not tested; app suspension is.

## F–H. Files, deployment, local environment

New: `supabase/functions/delete-account/{index.ts,handler.js,handler.test.mjs,README.md}`,
`tests/local/test_account_deletion_local.py`, this report. Updated only the three
authorized privacy/Data Safety/release audit documents. No Dart/Android/dependency changes.
Production deployment **NO**; migration/RLS changes **NONE**.

Dedicated project `account_delete_local_20261005_01`; workdir
`build/account-delete-validation-20261005`; API loopback port 57321; DB 57322.
CLI 2.117.0, Postgres 17.6.1.167, Auth 2.196.0, PostgREST 16.2, Edge Runtime 1.74.3,
Kong 2.8.1. Gateway JWT verification enabled. Existing stacks were not reset or removed.
Docker Desktop was initially stopped; starting it also resumed existing restart-policy
containers. Original 40 container IDs/names and 10 volume names were preserved.

## I–N. Actual JWT E2E and cleanup behavior

**Node unit tests 7/7; actual local Auth E2E 57 assertions PASS.**
The first E2E fixture setup failed because a returning review INSERT selected restricted
columns. Corrected the harness to `select=id`, without changing RLS or the function.
That run cleaned all fixture rows before the final successful run.

| Contract | Actual result |
|---|---|
| Missing Authorization / invalid JWT | 401 / 401 |
| Correctly signed expired local JWT | 401 |
| Revoked session JWT | 401, account retained |
| A attempts B ID in body / query | 400 / 400; no account removed |
| A self-delete, including suspended profile | 204 PASS |
| A Auth/profile/reviews | All removed |
| A reports and B report on A review | Removed by expected CASCADE |
| B account/profile/review and unrelated C report on B | Preserved; row snapshots equal |
| A Auth sessions/identities | Removed |
| Profile-less user self-delete | 204 PASS |
| Fixture public store | Preserved through account deletion |

Real signup provided all caller JWTs; profile/review/report fixtures were inserted with
user JWTs. Only store fixture and local failure trigger used trusted local SQL. Hard
deletion under test ran through the Edge Function and Auth Admin API, not direct SQL.

## O. Existing JWT after delete

| Request with A's old JWT | Observed status/result |
|---|---|
| Auth GET /user | 403 |
| Repeat function call | 401; no mutation |
| Own profiles SELECT | 200, empty |
| Own reviews SELECT | 200, empty |
| Public B review SELECT | 200, visible |
| Recreate A profile | 409, FK prevents resurrection |
| Create review / report | 403 / 403, RLS |

Deleting Auth does **not** instantly invalidate the token signature for PostgREST.
Public reads can work until expiry. The function uses online Auth and refuses replay.
Flutter must clear SDK/persisted sessions after confirmed success, stop refresh/retry
loops and clear cached account state. Remote logout failure must not prevent local
clear. Favorites are local, not deleted by this backend; UI policy must decide/explain
their handling. No automatic SSO retry: sign-in can create a fresh account.

## P. Retry / transaction boundary

Injected a dedicated local BEFORE DELETE profile trigger that raises an exception.
Function returned generic 503, and A Auth/profile plus all three reviews and reports
remained. A's session still worked. Removing the trigger and retrying succeeded.
The tested Auth version wraps hard delete and PostgreSQL FK cascades in one database
transaction: a cascade failure did not leave an Auth-success/DB-failure split.

HTTP response delivery is outside that transaction. A timeout can follow a committed
delete. Unit tests verify generic 503 for transport loss, 204 for a concurrent Admin
404 after successful verification. Actual replay after completed deletion is 401.
Never treat every 401 as deletion success. If response was lost, clear unsafe stale UI
state and reconcile through a trusted support/server process checking Auth/profile
absence before claiming completion. Retrying a still-valid caller is safe; never
recreate a profile or undo cascades. No distributed transaction was added.
Storage ownership restrictions, future FKs/hooks and provider logs need separate
review before deployment; the current app has no user-upload deletion path.

## Q–V. Verification and safety

- Secret scan: 9 task files, JWT/API-key/OAuth-secret/private-key patterns **0**;
  exact configured key/secret matches **0**. Test tokens/keys only in memory.
  Existing release APK SHA-256 unchanged; no server key was added to a client artifact.
- Flutter validation: not run; no Dart/shared source/native configuration changed.
- Local fixture Auth users/profiles/reviews/reports/stores each **0**, confirmed before teardown.
- Dedicated containers **0**, dedicated volumes **0** after exact-project stop with no backup.
- Existing Docker containers **40/40**, volumes **10/10** preserved by identity/name comparison.
- Production Auth delete/INSERT/UPDATE/DELETE/DDL/migration/RLS/deploy **ALL 0**.
- Google Cloud/Supabase configuration/OAuth changes **0**. Only production catalog SELECTs.
- Baseline 347 existing files: only the three authorized documents changed,
  other 344 hashes preserved; deletions 0, six task files added. The CLI automatically
  updated `supabase/.temp/cli-latest`; restored its original empty bytes and hash.
  Task files have no trailing whitespace. `git diff --check` flags only pre-existing
  integration_test/app_flow_test.dart lines 93/96; that file's hash is unchanged.
  Tracked diff remains the pre-existing 3 files, 187 insertions/32 deletions; task
  files/documents are untracked. Commit/push **NO**.

## W–X. Remaining risks and next phase

**IMPLEMENTED_LOCAL_NOT_DEPLOYED**, not production READY. Next: Flutter deletion
confirmation/error/ambiguous-response/session-clear integration and isolated UI tests;
then separately authorized deployment and disposable release test. Public deletion URL,
support workflow, retention exceptions/provider logs/backups, UGC gaps and final Data
Safety remain Play release blockers. No production destructive smoke is authorized here.

Release Maps **PASS**, root cause **MAPS_RELEASE_SHA_RESTRICTION**, per the user's
explicit current confirmation: actual production Maps key project received package
`com.burgermapkorea.app` + release SHA-1 restriction and rendering worked. This task
did not independently rerun Android or modify Google Cloud.

Sources checked: [Auth getUser](https://supabase.com/docs/reference/javascript/auth-getuser),
[Admin deleteUser](https://supabase.com/docs/reference/javascript/auth-admin-deleteuser),
[user deletion/JWT caveat](https://supabase.com/docs/guides/auth/managing-user-data),
[Edge Function authentication](https://supabase.com/docs/guides/functions/auth),
[tested Auth transaction implementation](https://github.com/supabase/auth/blob/v2.196.0/internal/api/admin.go#L533),
[tested live user/session validation](https://github.com/supabase/auth/blob/v2.196.0/internal/api/auth.go#L108).
