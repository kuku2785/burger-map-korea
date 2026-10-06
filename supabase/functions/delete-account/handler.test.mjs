import { test } from "node:test";
import assert from "node:assert/strict";
import { deleteAccount } from "./handler.js";

const id = "00000000-0000-4000-8000-000000000001";
const env = { SUPABASE_URL: "https://local.invalid", SUPABASE_SERVICE_ROLE_KEY: "test-only-placeholder" };
const request = (body = { confirmation: "DELETE" }, path = "", auth = "Bearer test-placeholder") =>
  new Request(`https://local.invalid/delete-account${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: auth },
    body: JSON.stringify(body),
  });
const verified = () => Response.json({ id, role: "authenticated", is_anonymous: false });
const never = () => { throw new Error("unexpected upstream request"); };

test("rejects missing auth, selectors, malformed confirmation and oversized input", async () => {
  assert.equal((await deleteAccount(request({}, "", ""), env, never)).status, 401);
  for (const req of [request({ confirmation: "DELETE", user_id: id }), request(undefined, `?user_id=${id}`),
    request({ confirmation: "NO" }), request({ confirmation: "X".repeat(300) }), request(null)]) {
    assert.equal((await deleteAccount(req, env, never)).status, 400);
  }
});
test("rejects wrong method and missing server configuration", async () => {
  assert.equal((await deleteAccount(new Request("https://local.invalid"), env, never)).status, 405);
  assert.equal((await deleteAccount(request(), {}, never)).status, 503);
});
test("online Auth denial never reaches admin API", async () => {
  for (const status of [401, 403, 500, 429]) {
    let calls = 0;
    const result = await deleteAccount(request(), env, async () => { calls++; return new Response("private upstream detail", { status }); });
    assert.equal(calls, 1);
    assert.equal(result.status, status < 429 ? 401 : 503);
    assert.equal((await result.text()).includes("private"), false);
  }
});
test("rejects anonymous, admin and malformed verified identities", async () => {
  for (const user of [{ id, role: "authenticated", is_anonymous: true }, { id, role: "service_role", is_anonymous: false },
    { id: "../another", role: "authenticated", is_anonymous: false }]) {
    let calls = 0;
    const result = await deleteAccount(request(), env, async () => { calls++; return Response.json(user); });
    assert.equal(result.status, 401);
    assert.equal(calls, 1);
  }
});
test("only verified identity goes to hard-delete API with server credentials", async () => {
  const calls = [];
  const result = await deleteAccount(request(), env, async (url, options) => {
    calls.push({ url, options });
    return calls.length === 1 ? verified() : new Response(null, { status: 200 });
  });
  assert.equal(result.status, 204);
  assert.equal(result.headers.get("Cache-Control"), "no-store");
  assert.equal(calls[0].options.headers.Authorization, "Bearer test-placeholder");
  assert.equal(calls[1].url, `${env.SUPABASE_URL}/auth/v1/admin/users/${id}`);
  assert.equal(calls[1].options.headers.Authorization, `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`);
  assert.deepEqual(JSON.parse(calls[1].options.body), { should_soft_delete: false });
});
test("concurrent deletion 404 is safe, server failures stay generic", async () => {
  for (const status of [404, 500, 403]) {
    let calls = 0;
    const result = await deleteAccount(request(), env, async () => ++calls === 1 ? verified() : new Response("private", { status }));
    assert.equal(result.status, status === 404 ? 204 : 503);
    assert.equal((await result.text()).includes("private"), false);
  }
});
test("transport failure or lost delete response never claims success", async () => {
  for (const failingCall of [1, 2]) {
    let calls = 0;
    const result = await deleteAccount(request(), env, async () => {
      if (++calls === failingCall) throw new Error("private upstream detail");
      return verified();
    });
    assert.equal(result.status, 503);
    assert.deepEqual(await result.json(), { error: "temporarily_unavailable" });
  }
});
