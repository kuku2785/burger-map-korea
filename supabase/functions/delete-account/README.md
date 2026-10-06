# delete-account

Status: **IMPLEMENTED_LOCAL_NOT_DEPLOYED**. No Flutter integration or production deployment.

`POST /functions/v1/delete-account`

- `Authorization: Bearer <current user's access token>`
- `Content-Type: application/json`
- Exact JSON body: `{"confirmation":"DELETE"}` (maximum 256 bytes)
- No query parameters, user ID, or extra body fields are accepted.
- Native clients also provide the project's public `apikey` for the gateway.

The gateway's default `verify_jwt = true` remains enabled. The handler independently
calls Auth `GET /auth/v1/user` with the caller JWT; it never authorizes decoded
claims or editable metadata. Only that verified, non-anonymous authenticated user's
ID reaches `DELETE /auth/v1/admin/users/{id}` with `should_soft_delete: false`.
The server reads only built-in `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.
Neither belongs in Flutter, dart-defines, assets, request bodies, or logs.

Responses:

| Status | Meaning |
|---|---|
| 204 | Hard delete succeeded, or user disappeared concurrently after verification |
| 400 | Invalid confirmation, oversized body, query, or extra fields |
| 401 | Missing/invalid/expired/revoked JWT, deleted user, or unsupported identity |
| 405 | Use POST |
| 503 | Configuration/upstream/network failure; completion may be ambiguous |

After success a replay receives 401 because the user no longer exists. This is safe
idempotency of the resulting state, not a promise of identical HTTP responses.
Never interpret a general 401 as proof of deletion. A lost success response requires
trusted reconciliation; do not sign in automatically (SSO can create a new account).
The function neither logs nor returns upstream errors, IDs, emails, tokens or keys.
Native Android is the current scope; web CORS is not provided.

UI phase must explain irreversible app-account/review/report deletion and request
confirmation, then clear local session after confirmed success. It must distinguish
deleting Burger Map from deleting the Google account. The Admin API does not require
a fresh Google password/SSO challenge: this contract requires a valid live session,
not a recent-login-age policy. Do not equate token refresh with fresh authentication.

## Validation

Unit tests (Node 24, no external packages):

```text
node --test supabase/functions/delete-account/handler.test.mjs
```

Integration: `tests/local/test_account_deletion_local.py`, guarded to exact dedicated
project `account_delete_local_20261005_01`, API `http://127.0.0.1:57321`, database
container `supabase_db_account_delete_local_20261005_01`. Never repoint this runner
at a shared project. It requires an initially empty database with repository migrations
and this function served. It creates and finally removes synthetic fixtures.

Prepare an isolated CLI workdir under ignored `build/`; run `supabase init` there,
set project ID above, remap default 543xx ports to 573xx, and copy migrations/functions.
Keep `verify_jwt = true`; disable seeds. Start only DB, Auth, REST, Kong, Edge Runtime
(`start --exclude realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,logflare,vector,supavisor`).
Run `functions serve` with that same workdir. Capture `status -o json` in a process,
never terminal/logs, and supply these environment variables only to the test process:

- `SUPABASE_LOCAL_API_URL`, `SUPABASE_LOCAL_ANON_KEY`, `SUPABASE_LOCAL_SERVICE_KEY`
- `SUPABASE_LOCAL_JWT_SECRET` (for an expired, locally signed test token)
- `SUPABASE_LOCAL_DB_CONTAINER`, `SUPABASE_LOCAL_DOCKER`

Snapshot existing Docker resources first. After fixture cleanup, use `stop` with the
exact dedicated `--project-id`, dedicated `--workdir`, and `--no-backup`; never `--all`
or global prune. Assert original container IDs/names and volumes still exist.
No `.env`, production linking, `db push`, deployment or production credentials are used.

See [validation and boundaries](../../../docs/account-deletion-backend-local-2026-10-05.md).
