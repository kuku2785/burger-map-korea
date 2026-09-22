# Auth/Menu/Review security revalidation — 2026-09-22

## Scope and safety

This is a local-only validation record for `0001_init_store_schema.sql` followed
by `20260922050439_auth_menu_reviews.sql`. No production database, Auth user,
RLS policy, migration history, `.env`, Flutter code, or existing migration was
changed. The report does not contain an API key, token, password, URL with
credentials, or fixture identifier.

## Test defects remediated

`tests/local/run_auth_menu_reviews_security_revalidation.py` replaces the
previous narrow runtime assertion path for this validation. It is a local-only
runner that accepts its credentials exclusively through process environment
variables and refuses a non-loopback API URL.

- **Anonymous claim:** creates a real local anonymous Auth session, then reads
  a disposable local `SECURITY INVOKER` view through PostgREST. It asserts both `auth.uid()` and
  `auth.jwt()->>'is_anonymous'` are non-null and match the Auth-issued session.
- **NULL assertions:** the SQL helper uses `IS DISTINCT FROM true`; a NULL
  boolean is an assertion failure.
- **Other-user PATCH:** snapshots `id`, `store_id`, `user_id`, `rating`,
  `content`, and `is_hidden` through the trusted local fixture path before the
  request. It sends `Prefer: return=minimal,count=exact`, requires an actual
  zero-row count, then requires the whole snapshot to be identical.
- **Broader security contract:** the runner covers normal profile/review CRUD,
  ownership forging, restricted client/system columns, review and nickname
  boundaries, duplicate/racing review writes, report attacks, hidden and
  non-public visibility, aggregate lifecycle, account/review cascade, store
  `RESTRICT`, invoker views, helper ACL/search path, and private-schema local
  API non-exposure.

The runner uses `return=minimal` plus an explicit permitted-column read for
profile creation. A generic `return=representation` asks PostgREST for the
non-readable `is_suspended` column and correctly receives 403; the runner does
not solve that boundary by granting the column.

## Confirmed migration defect and fix

The original profile INSERT/UPDATE policies directly evaluated
`is_suspended`. Because `authenticated` deliberately lacks SELECT on that
column, PostgREST profile creation returned 403 even for a normal Auth session.

- `profiles_owner_insert` no longer reads `is_suspended`; the client cannot
  supply that column and the database default remains `false`.
- `profiles_owner_update` now uses the existing fixed-search-path
  `SECURITY DEFINER` helper `burger_map_private.can_contribute()`, which checks
  the caller's `auth.uid()` and the profile suspension state without exposing
  the column.
- No client SELECT/INSERT/UPDATE privilege was added for `is_suspended`; no
  broad grant or permissive policy was added.

## Fresh local execution attempt

| Item | Result | Evidence |
| --- | --- | --- |
| Existing migration `0001` fresh application | PASS | `supabase db reset` applied it before the new migration. |
| Auth/Menu/Review migration fresh application | PASS | `supabase db reset` applied `20260922050439` immediately after `0001`. |
| SQL/RLS and REST/Auth suite | PASS | 195 assertions on a final fresh disposable DB. |
| Profile privacy and suspension regression | PASS | Normal create/read and nickname update work; direct/insert/update access to `is_suspended` is denied; suspended contribution is denied. |
| Claims suite | PASS | Actual normal and anonymous Auth sessions reach `auth.uid()` and `auth.jwt().is_anonymous` through PostgREST. |
| Review/report attack matrix | PASS | Ownership, immutable/system columns, duplicate review/report, hidden/non-public targets and client report reads/writes are denied as required. |
| Cascade and aggregate lifecycle | PASS | Auth-user cascade, direct review-to-report cascade, store RESTRICT, and all requested count/average transitions were executed. |
| Views/helper and stores regression | PASS | Invoker/security/ACL contract plus existing stores 13-column, public-policy and no-client-write checks passed. |
| Transaction failure simulation | PASS | An injected `SELECT 1 / 0` in a disposable copy failed; no Auth/Menu/Review objects or applied migration history remained. |

The final fresh reset restored the unmodified migration copy and applied exactly
`0001` then `20260922050439`. Local credentials were read only into the test
process and removed after every run.

## Static verification completed

- Python bytecode compilation of the new runner: PASS.
- Source-level checks for JSON request claims, NULL-safe assertion form, actual
  claim probe, and PATCH snapshot assertion: PASS.
- Focused diff whitespace check for the new runner: PASS.

The static checks supplement the executed local integration suites.

## Production configuration observations

- Production changes in this task: **NONE**.
- The production Data API exposed-schema setting for `burger_map_private`
  remains **NOT VERIFIED**. The schema does not yet exist in production, and a
  read-only configuration inspection was unavailable in this environment. It
  must not be inferred from the local config.
- The previously observed local/production `service_role` difference for
  `stores` remains a **NON-BLOCKER for anon/authenticated client paths** and a
  constraint on future privileged production smoke fixtures. This runner uses
  only the disposable local service credential for trusted fixture assertions;
  it does not justify any production grant change.

## Remaining blockers

The local security revalidation has no unresolved Critical or High finding.
Before any production apply decision, the production Data API exposed-schema
list remains read-only **NOT VERIFIED** and must explicitly exclude
`burger_map_private`. This is not evidence that the schema is exposed.

## Current verdict

**AUTH_MENU_REVIEW_SECURITY_REVALIDATED**

All required fresh local migration, Auth, REST, SQL/RLS, lifecycle and rollback
checks passed. Production apply remains out of scope; no production change was
made and its exposed-schema configuration still needs a read-only pre-apply
check.
