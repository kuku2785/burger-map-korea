# Account Deletion Phase 2 — Flutter local validation

**ACCOUNT_DELETION_FLUTTER_LOCAL_PASS**

Status: **IMPLEMENTED_AND_TESTED_LOCAL**. Backend **IMPLEMENTED_LOCAL_NOT_DEPLOYED**.
Production **NOT_DEPLOYED**. No production function invocation or user deletion.

## A–D. Repository, entry and confirmation

Branch `nearby-store-sort`, HEAD `f152a65121f7488df89cd3324ca6401170b7a105`.
The existing persistent public map has optional login/nickname/logout actions supplied
by AuthGate. Added an authenticated-only account-delete action beside logout, without
introducing a settings architecture. Guests see no delete action.

The scrollable confirmation explains deletion of the Burger Map profile, authored
reviews/reports and reports linked to the user's reviews, with no recovery. It states
that the Google account is unaffected and device favorites remain. Cancel receives
initial focus. Confirmation uses error colors, 48dp minimum targets, a labelled entry,
destructive-action semantics and live progress/error announcements. Dialog dismissal
and confirm/cancel are blocked during the request. TalkBack/device smoke remains unrun.

## E–G. Client and ownership contract

Re-read the backend handler, README and tests before implementation.

| Item | Implemented contract |
|---|---|
| Function | `delete-account` |
| Method | POST |
| Authentication | Current session access token in Authorization Bearer; normal public apikey |
| Body | Exactly `{"confirmation":"DELETE"}` |
| Query/user UUID | None |
| Success | Only HTTP 204 |
| 401 | Safe authentication message; no success or forced logout |
| 400/404/405/503/other status | Safe failure; existing session retained |
| Network/30-second timeout | Completion uncertain; session retained, explicit retry possible |

Extended existing AuthRepository/AuthController rather than creating another state
owner. Controller and repository both prevent parallel deletion. Logout/nickname
submission cannot race deletion through the controller. Confirmation is bound to the
account that opened it; an account switch disables it. Late completion cannot sign
out a newly signed-in different user. Earlier profile reads cannot restore deleted state.
The client never invokes Admin APIs and contains no server credentials.

## H–J. Success, failure and favorites

After 204, SDK signOut(local) removes in-memory Auth state before its remote logout
call in installed gotrue 2.27.2. Remote logout errors or a 5-second timeout do not block
cleanup once memory is clear. The same SharedPreferencesLocalStorage instance used
by Supabase initialization is then explicitly cleared and awaited. Its key matches
the SDK default, preserving existing login persistence. Invalid configuration still
avoids client initialization. No new dependency or runtime data-source policy.

AuthController clears profile/session gate state; the existing AuthGate returns to
guest actions on the same public map. Review UI already listens to AuthController,
clears its editor and reloads on a changed user identity. Existing review/report
regressions were retained. Local favorites remain untouched, matching logout policy.

Non-204/transport errors do not call signOut or remove persisted session. Safe errors
never render raw server responses or exceptions. A timeout does not mean rollback;
the UI says deletion completion could not be confirmed. A subsequent 401 is not
proof of deletion and does not trigger automatic login/account recreation.

A persistent-storage failure *after* server success is separately represented as
`accountDeletionCleanup`: do not claim the server deletion failed. Warn that device
cleanup was incomplete; support reconciliation is required. Storage hardware failure
and cross-process/browser session races are not a guarantee of recoverable local state.

## K. Files

- `lib/features/auth/domain/auth_repository.dart`: delete contract and cleanup failure kind.
- `lib/features/auth/data/supabase_auth_repository.dart`: function invocation, success-only cleanup.
- `lib/features/auth/application/auth_controller.dart`: busy/ownership/stale-response handling.
- `lib/features/auth/presentation/account_deletion_button.dart`: new confirmation widget.
- `lib/features/map/presentation/map_screen.dart`: existing account toolbar integration.
- `lib/main.dart`, `lib/features/stores/data/supabase_store_locations_loader.dart`: shared SDK storage wiring.
- `test/features/auth/account_deletion_test.dart`, `account_deletion_repository_test.dart`: new tests.
- Existing AuthRepository doubles in auth_bootstrap/auth_controller/auth_gate_widget/
  guest_exploration/store_review_section tests: new interface method only.
- This report and the three authorized policy/release documents: current status.

## L–O. Validation

- `dart format`: changed Dart files formatted.
- Focused deletion tests: **23/23 PASS** (12 controller/widget + 11 repository).
- Full `flutter test --no-pub`: **378/378 PASS**, including prior 355 tests.
- `flutter analyze --no-pub`: **No issues found**, 20.8 seconds. Two initial style
  diagnostics fixed; focused tests rerun afterward, **23/23 PASS**.
- Repository tests use a disposable loopback HTTP fixture with synthetic tokens and
  SharedPreferences mock storage. Widget/controller tests use a fake repository/map.
  No real Supabase project, OAuth flow, production .env or real JWT is used by tests.
- Verified exact HTTP method/body/headers, no selectors, success, unauthorized/server
  failure, duplicate requests, retry, raw-error sanitization, memory/persisted cleanup,
  deleted-user logout failures, account switching, stale reads and disposed context.
- Initial tests caught a non-const Semantics construction and the widget binding's
  HTTP-400 stub; corrected the widget and explicitly enabled the local HTTP fixture.
  No legitimate test was removed or weakened.
- Secret scan: all 18 task files, actual JWT/key/OAuth-secret/private-key patterns
  **0**, exact configured credential matches **0**. Trailing whitespace **0**,
  broken local document links **0**. Existing release APK hash unchanged.

## P–S. Safety

Production deployment **NO**. Production Auth delete, INSERT, UPDATE, DELETE, DDL,
migration, RLS and external Google/Supabase settings changes **ALL 0**.
Backend code/schema untouched. No APK build/install or real-account interaction.
Commit/push **NO**. Existing user changes are preserved; no staging/reset/clean.

Baseline 353 existing files: 14 task-related files changed, other **339 hashes
identical**, deleted **0**; four task files added. In particular the pre-existing
dirty PROJECT_STATUS.md, README.md, integration_test/app_flow_test.dart and all
backend files remain byte-identical. Final tracked diff is 14 files,
344 insertions/34 deletions including the pre-existing 187 insertions/32 deletions;
untracked new code/tests/docs and policy documents are listed separately by git status.

## T–U. Remaining work

Production remains NOT_DEPLOYED; a production invocation would currently fail, not
delete an account. Next phase requires separately authorized backend deployment,
disposable-account end-to-end release validation, TalkBack/device confirmation and
restart/session verification. External deletion URL/support workflow and provider
retention/backups remain policy work. This phase is not a production-readiness verdict.

SDK/API references checked alongside installed source:
[Flutter invoke](https://supabase.com/docs/reference/dart/functions-invoke),
[Flutter signOut](https://supabase.com/docs/reference/dart/auth-signout).
Transaction/JWT caveats and FK scope remain in the
[backend report](account-deletion-backend-local-2026-10-05.md).
