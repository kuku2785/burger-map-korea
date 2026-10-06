# Account Deletion Production preflight — 2026-10-06

**PRODUCTION_DELETE_FUNCTION_DEPLOY_READY — WAITING FOR APPROVAL #1**

This is readiness to deploy the reviewed function, not production E2E completion.
No production function invocation, deployment, account creation or deletion occurred.

## Repository and current-code review

Branch `nearby-store-sort`; HEAD `f152a65121f7488df89cd3324ca6401170b7a105`.
Read AGENTS.md, current backend entrypoint/handler/README/tests and current Flutter
repository/controller/confirmation/storage wiring and tests. Existing dirty changes
remain unstaged. Root `supabase/config.toml` does not exist. The function uses only
the relative `handler.js` dependency; no deno config, import map or external module.
The backend README's “No Flutter integration” sentence is historical; actual Flutter
integration exists and its current report supersedes that sentence. No source fix made.

| Check | Evidence/result |
|---|---|
| JWT | Required Bearer header; online Auth GET /user before deletion |
| Owner | ID from verified non-anonymous authenticated Auth user only |
| Body/query | Exact confirmation-only body; all query and extra fields rejected |
| Privilege | Service role read only from server environment |
| Logs/errors | No handler logging; generic error responses, no upstream data returned |
| Retry | Deleted user replay rejected; concurrent Admin 404 after verification returns 204; transport failure stays ambiguous |
| Flutter | POST delete-account, current JWT, exact body, no user ID/query |
| Success | Only 204; SDK local signout plus awaited persisted-session removal |
| Failure | 401/non-204/transport do not request logout; safe message and retry |
| UI | Auth-only entry; destructive confirmation; loading/duplicate guard; stale/disposed safeguards |
| Favorites | Retained; confirmation states this explicitly |

Fresh tests: backend Node **7/7 PASS**; Flutter deletion tests **23/23 PASS**.
Full Flutter **378/378** and analyze PASS are the preceding Phase 2 results, not
rerun in this preflight. Backend actual local Auth 57 assertions are prior evidence;
no isolated Auth stack was restarted during this read-only production preflight.

## Production read-only evidence

Target: **burger-map-korea-dev**, ref **eoiwfprghyyguthdtayx**.
Supabase MCP `list_edge_functions` returned `[]`: function count **0**,
`delete-account` **NOT_DEPLOYED**.

One catalog/count query snapshot:

| Table/count | Rows |
|---|---:|
| stores | 280 |
| public stores: verified AND active | 237 |
| menus | 28 |
| burger_map_private.menu_evidence | 29 |
| profiles | 2 |
| reviews | 0 |
| review_reports | 0 |

Fresh pg_constraint inspection:

| Parent | Child.column | ON DELETE |
|---|---|---|
| auth.users | profiles.id | CASCADE |
| profiles | reviews.user_id | CASCADE |
| profiles | review_reports.reporter_user_id | CASCADE |
| reviews | review_reports.review_id | CASCADE |
| stores | reviews.store_id | RESTRICT |
| stores | menus.store_id | RESTRICT |
| stores | burger_map_private.menu_evidence.store_id | RESTRICT |
| menus(store_id,id) | burger_map_private.menu_evidence.(store_id,menu_id) | RESTRICT |

Auth users also cascade to identities, sessions, mfa_factors, mfa_recovery_code_sets,
oauth_authorizations, oauth_consents, one_time_tokens, webauthn_challenges and
webauthn_credentials. auth.scim_users.user_id instead uses SET NULL.
App cascades match the implementation assumptions. Provider audit/log/backups are
not promised erased by this function. No individual user identity was selected/read.

## Environment and credential boundary

CLI `secrets list --project-ref eoiwfprghyyguthdtayx -o json` succeeded. Output was
captured in memory and reduced to names only: **custom secrets []**. Neither values
nor digests were printed or persisted. Required names are `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`, documented platform-injected defaults; custom secret
creation and `secrets set` are unnecessary. The empty custom list does not mean
these built-ins are missing. Their actual runtime contents are **not observed before
deployment**. Current handler fails closed with 503 if configuration is missing.

[Default server variables](https://supabase.com/docs/guides/functions/secrets#default-secrets)
and [JWT platform verification](https://supabase.com/docs/guides/functions/auth-headers)
checked 2026-10-06. Keep gateway `verify_jwt = true` and handler online Auth validation.
Do not disable verification to work around failures.

APK 4017 scan: packaged .env false; service-role JWT, sb_secret key, OAuth client
secret, DB-password URI and locally known private credential matches **all 0**.
Current lib/backend source literal secret patterns **0**. Public Maps/Web OAuth
client IDs/publishable config are distinct from admin secrets; none was printed.
New Flutter release artifact has not yet been built and must be scanned separately.

## Concrete deployment plan — NOT EXECUTED

Use the existing Supabase connector to avoid adding/changing root configuration.
Exact deploy tool contract reviewed; prepare this payload after approval, reading
only the two reviewed files and rechecking hashes:

```text
supabase_deploy_edge_function
  project_id: eoiwfprghyyguthdtayx
  name: delete-account
  verify_jwt: true
  entrypoint_path: index.ts
  files:
    index.ts  <- supabase/functions/delete-account/index.ts
    handler.js <- supabase/functions/delete-account/handler.js
```

| Upload file | SHA-256 |
|---|---|
| index.ts | b5af69256edee49ffeea1d3d295ad2fbd928ea96a67b183c4c6c79b6e4dfba2e |
| handler.js | 07c982e26f720f9c0aa8bd8b92db67e454b0e486452c943900712f42e99054fc |

Equivalent CLI command prepared from installed CLI 2.117.0 `functions deploy --help`
(not executed; connector payload above is the selected method):

```powershell
& 'C:\Users\jeong\AppData\Local\npm-cache\_npx\6f1b058a4d9555af\node_modules\@supabase\cli-windows-x64\bin\supabase.exe' functions deploy delete-account --project-ref eoiwfprghyyguthdtayx --use-api --workdir 'C:\Users\jeong\burger-map'
```

No `--no-verify-jwt`, pruning, migration, linking, credential creation or unrelated
function is included. Since there is no deployed function now, expect its first
deployment version; record the actual returned version and verify the remote list,
entrypoint/code and verify_jwt setting instead of assuming a version number.

**Approval #1 scope:** deploy only this reviewed function, then non-destructive smoke
with no Authorization and an invalid dummy JWT (expect rejection). No valid-user
deletion request. No extra diagnostic function. Anonymous rejection does not prove
the privileged Admin path; that remains for separately approved test-account E2E.

## Release device preparation

- `adb devices -l`: Samsung **SM-N981N**, Android **13**, connected/authorized.
- At inspection: Awake, keyguard showing false/input restricted false.
- Installed package **com.burgermapkorea.app**, versionCode **4017**, versionName 1.0.0;
  no DEBUGGABLE flag.
- Installed APK SHA-256 matches the existing local release APK exactly:
  `7f7eb6550a7c84ea5d83448d52e5c02bac15d8e3a1324990887f2b36088b1562`.
- APK signature verification PASS; release SHA-1
  `3D:F2:42:D9:BE:EE:AC:42:97:3F:B5:1B:23:13:49:C2:54:C2:8F:4C`.
- **4017 predates Phase 2 deletion UI.** It cannot validate the new deletion flow.
  Prepare a new signed release APK from this unchanged source, then inspect its
  public build defines/signature/package and secret scan before an in-place install.
  Existing secure wrapper accepts only production URL/publishable/Maps/Web client ID
  and production flags. No server secret belongs in the build. No build/install/app
  launch/logout/data-clear was performed in this preflight.
- Google login/Maps PASS are prior results; not retested here.

## Approval #2 and subsequent E2E plan — NOT AUTHORIZED YET

No deletion target has been designated. The existing two profiles are protected;
neither is assumed disposable. After deployment and a user's explicit test-account
selection, read minimal identifying information, Auth/profile existence, its review
and report counts plus reports on its reviews. Report expected cascades and STOP at
`PRODUCTION_TEST_ACCOUNT_DELETE_READY` for the separate final deletion approval.

Only after that approval: release UI test-account login → confirmation → delete →
204 → guest UI/local cleanup → force-stop/restart → no session restoration; verify
target Auth/profile/reviews/reports removed as applicable, unrelated users and store/
menu/evidence baseline preserved. No new profile/review/report fixtures before their
specific mutation scope is disclosed and authorized; optional review maximum 1.

An old JWT check is optional and only possible if the test token can stay in process
memory without extraction to files/logs. Otherwise report it skipped; do not weaken
the release app or log tokens. Any contribution replay needs the test-account mutation
budget to cover an unexpected acceptance. Public reads and privileged contribution
are separate results. Unexpected outcomes: STOP, no manual SQL deletion, RLS/schema/
Auth changes or source hotfix.

## Safety and stop point

Production Auth delete / INSERT / UPDATE / DELETE / DDL / migration / RLS / deploy /
external setting changes **ALL 0**. Application/backend source changes **NONE**.
Commit/push **NO**. This new report is the only intended repository addition.
Approval gates come directly from the user's attached IMPORTANT SAFETY GATE and
sections 6/10, not an inferred skill requirement.

**STOP: awaiting explicit approval #1 for deployment only.**
