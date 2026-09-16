# AGENTS.md — Burger Map Korea

## 0. Purpose

Common operating rules for any AI coding agent working in Burger Map Korea.

This file is model-agnostic. It should remain valid for Codex, GPT-based agents, Astra-class agents, Antigravity, IDE agents, and similar tools.

Keep only stable project rules here. Put current progress, test counts, branches, SHAs, and release status in `PROJECT_STATUS.md`.

---

## 1. Project

Burger Map Korea is a Flutter + Google Maps + Supabase application for discovering burger stores in Seoul.

Core areas:

- Flutter client
- Google Maps
- Supabase public store data
- search and burger-style filters
- favorites
- marker clustering
- current location
- accessibility
- store discovery/review/publishing data pipeline

---

## 2. Sources of truth

Use this order:

1. User's explicit current instruction
2. Actual repository state, code, tests, Git state, schema, and configuration
3. More specific repository-local instructions
4. `PROJECT_STATUS.md`
5. `README.md`
6. `CODEX_CONTEXT.md`
7. This `AGENTS.md`
8. Existing repository conventions
9. General best practices

If documentation conflicts with the actual repository, inspect and trust the repository.

A user request does not implicitly authorize exposing secrets, destroying unrelated work, fabricating evidence, mutating production data, or rewriting Git history.

---

## 3. Default workflow

For every task:

1. inspect relevant current state,
2. choose the smallest correct scope,
3. change only what is required,
4. verify proportionally,
5. report only completed work.

Before editing, inspect as applicable:

- `git status`
- current branch
- relevant implementation
- nearby tests
- relevant schema/config
- `PROJECT_STATUS.md` when current status matters

Do not invent paths, APIs, schema fields, enum/status values, branch state, test results, store counts, IDs, or repository conventions.

If unsure, inspect first.

---

## 4. Scope and user work

Only modify files required for the user's request.

Do not:

- refactor unrelated code
- rename unrelated symbols
- reformat unrelated files
- upgrade dependencies without need
- fix unrelated warnings
- touch unrelated untracked/generated files
- expand into optional cleanup without reason

Assume pre-existing changes belong to the user.

Never discard, reset, overwrite, stage, commit, or claim unrelated user work.

A dirty working tree is not permission to clean it.

---

## 5. Safe autonomy

Without additional approval, the agent may:

- read/search repository files
- inspect Git state and diffs
- make local reversible edits
- add/update tests
- run formatters
- run static analysis
- run relevant tests
- run local builds
- inspect schemas/config
- perform read-only validation
- create local/versioned review outputs

Do not interrupt routine reversible work with unnecessary confirmation requests.

Ask only when a missing decision materially changes product behavior, data policy, or an irreversible/external action.

---

## 6. Explicit authorization required

Do not perform these unless the user explicitly requests the specific action:

- commit
- push
- create PR
- merge
- direct push to `main`
- delete branches
- rewrite Git history
- mutate production Supabase data
- alter RLS/security policy
- publish a release
- submit to an app store
- change cloud billing
- rotate credentials
- delete user datasets
- overwrite important review CSVs in place

Read-only inspection does not require authorization.

---

## 7. Git safety

Never use:

- `git push --force`
- `git push --force-with-lease`
- destructive reset against user work
- history rewriting on shared branches

unless the user explicitly requests that exact history rewrite and the consequences are clear.

When committing:

- stage only task-related files
- inspect the staged diff
- exclude secrets
- exclude unrelated CSV/data files
- exclude unrelated generated files
- exclude unrelated user changes

Avoid `git add .` when unrelated changes exist.

---

## 8. Secrets

Never expose, print, log, commit, or copy into generated artifacts:

- `.env` contents
- API keys
- access tokens
- passwords
- Supabase service-role keys
- signing credentials
- private certificates
- secret-bearing config

You may report that a secret exists, is missing, or appears misconfigured without revealing its value.

If output exposes a secret, do not repeat it.

Do not modify credential files unless explicitly requested.

---

## 9. Production runtime

Preserve current production safety unless the user explicitly changes the policy.

Protected invariants:

- production/release uses the intended Supabase production path
- invalid production config fails safely
- production does not silently fall back to pilot data
- production does not silently fall back to staging data
- debug-only staging data does not leak into release artifacts
- release artifacts do not retain staging references or staging store IDs

Changes to runtime selection, release config, assets, or packaging must verify these invariants.

---

## 10. Supabase

Preserve the current public visibility rule unless explicitly changed:

`verification_status = verified AND is_active = true`

Do not add client-side write paths unless requested.

Production mutation includes:

- INSERT
- UPDATE
- DELETE
- mutating RPC
- schema migration
- RLS change
- verification-status change
- activation/deactivation

All production mutation requires explicit user authorization.

For bulk imports/updates:

1. validate locally,
2. dry-run,
3. report counts/failures,
4. perform real write only after authorization.

A CSV parsing successfully does not mean it is publish-safe.

---

## 11. Location and privacy

Preserve current privacy behavior unless explicitly changed.

Protected rules:

- foreground-only location usage
- do not persist location coordinates
- do not log location coordinates
- do not send location coordinates to Supabase
- Android requests foreground `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` together
- approximate-only permission must support current location and nearby sorting with accuracy guidance
- do not add `ACCESS_BACKGROUND_LOCATION`

Changes involving location, permissions, analytics, logging, networking, or persistence must verify these rules.

---

## 12. Flutter architecture

Follow existing architecture and naming conventions.

Before creating a new controller, service, repository, model, state owner, abstraction, or dependency, check whether an existing component already owns that responsibility.

Avoid duplicate state ownership.

Do not add a dependency when the existing stack can solve the task cleanly.

Preserve neighboring behavior unless the task explicitly changes it.

Important interactions include:

- map rendering
- markers/clustering
- search
- burger-style filters
- favorites
- current location
- nearby sorting
- accessibility
- store visibility
- production runtime selection

---

## 13. Failure-state integrity

Do not convert operational failure into a valid-looking business result.

Examples:

- failed favorites load != empty favorites
- failed store request != no stores exist
- failed provider search != store does not exist
- failed location request != fabricated coordinates
- failed production config != permission to use pilot/staging

Prefer explicit, recoverable error states.

Do not overwrite valid state because a later read failed.

---

## 14. Store-data pipeline

Keep these stages separate:

- raw/source
- candidate discovery
- review/audit
- unresolved/user-decision
- publish-ready
- production

Do not silently promote records between stages.

Never fabricate or guess:

- existence
- operating status
- address
- coordinates
- branch identity
- burger style
- franchise status
- closure status
- evidence URLs
- place/API IDs
- source timestamps

One provider failing to find a store is not proof of nonexistence.

Insufficient/conflicting evidence must remain unresolved under the existing project policy.

---

## 15. Evidence rules

Evidence must be real, relevant, and traceable.

Never:

- invent evidence URLs
- construct guessed URLs from patterns
- claim a source was checked when it was not
- use a generic homepage as proof of a specific branch without support
- reuse evidence from a similar branch
- use search-result absence alone as proof of closure/nonexistence

If project policy requires evidence for publish-ready data, missing evidence is a validation failure.

Preserve uncertainty instead of manufacturing certainty.

---

## 16. Store-data validation

Before producing publish-ready or Supabase-ready data, validate applicable items:

- required columns/values
- candidate/source ID uniqueness
- UUID/ID formats
- store/address duplication
- potential branch duplication
- coordinate numeric validity
- geographic plausibility
- suspicious/shared coordinates
- target administrative district
- actual burger-sales relevance
- inclusion/exclusion rules
- franchise/chain rules
- `burgerStyle` allowed values
- verification/status allowed values
- evidence URL validity
- source/source-type mapping
- date formats
- Supabase schema mapping
- null/empty policy

Do not invent new enum/status/source values because they sound reasonable.

Repository schema and validators are authoritative.

---

## 17. Review-file safety

User-owned review CSVs are protected project artifacts.

Do not delete or overwrite them unnecessarily.

Prefer:

- new versioned outputs
- explicit patch files
- deterministic regeneration

over destructive in-place replacement.

Preserve established naming conventions.

Do not mix rejected, unresolved, candidate, and publish-ready records unless the schema requires it.

---

## 18. Verification

Verification must be proportional to risk.

### Documentation-only
Usually verify diff and formatting/links.

### Localized Flutter logic
Run as applicable:
- formatter
- focused tests
- `flutter analyze`

### Cross-feature Flutter change
Run:
- focused tests
- broader Flutter tests when interactions may be affected
- `flutter analyze`

### Map/location/permissions/persistence/favorites/filters/sorting/clustering/accessibility
Run focused behavior tests plus relevant interaction tests.

If native Android config, manifest, Gradle, plugins, permissions, or platform channels change, run Android/native verification when supported.

### Python/data pipeline
Run as applicable:
- relevant Python tests
- schema/enum/date/coordinate validation
- duplicate checks
- evidence checks
- publish/import dry-run validation

Never report a check as passed unless it actually ran and passed.

---

## 19. Test integrity

If a test fails:

1. determine whether your change caused it,
2. fix failures caused by your change,
3. do not weaken legitimate tests merely to get green output,
4. report unrelated pre-existing failures separately.

Never delete, skip, or relax a valid test solely to hide a regression.

Do not report historical test counts as newly verified results.

Observed current output is authoritative.

---

## 20. Release-sensitive work

Treat these as high-risk:

- production runtime selection
- release build configuration
- Android permissions
- Google Maps key wiring
- Supabase config
- asset inclusion/exclusion
- signing
- package/application ID
- RLS
- production visibility policy
- production migrations

Inspect real configuration and verify the release-specific path.

Do not claim release readiness from unit tests or debug builds alone.

---

## 21. External/current facts

When work depends on facts that may change, use current authoritative sources when available.

Examples:

- API policies
- Play Store requirements
- Google Maps/Places behavior
- Supabase behavior
- Flutter/package documentation
- store operating status

Keep external facts separate from locally verified repository facts.

Do not treat old project notes as authoritative for changing external facts.

---

## 22. Definition of done

A task is complete when:

- requested work is actually done
- unrelated behavior is preserved
- unrelated files were not modified
- relevant verification was performed
- no secret was exposed
- no unauthorized production mutation occurred
- no user work was destroyed
- no store evidence was fabricated
- unresolved uncertainty is reported honestly

If implementation is complete but a required verification cannot be performed, report that distinction clearly.

---

## 23. Completion report

Keep reports concise and factual.

Include:

- what changed
- files changed
- verification actually run
- failures/skipped checks
- remaining risk or user decision
- commit/push/PR status when relevant
- for data work: row counts and output path

Do not paste large diffs unless requested.

Do not report planned actions as completed.

---

## 24. Stop conditions

Stop before the next action only when:

1. it is irreversible or externally visible and not authorized,
2. it would mutate production data without authorization,
3. it would expose a secret,
4. it risks destroying unrelated user work,
5. it requires a genuine product/data-policy decision with materially different outcomes,
6. required facts cannot be established from repository state, tests, schema, or reliable evidence.

Otherwise continue with the safest reasonable local implementation.

---

## 25. Final principle

Be strict about evidence, secrets, production data, Git history, user-owned files, release behavior, and privacy.

Be autonomous about inspection, local edits, tests, analysis, and reversible fixes.

When unsure about repository state, inspect it.

When unsure about current external facts, verify them.

When unsure about store evidence, do not invent it.

When a smaller correct change exists, prefer it.
