// Auth is checked online for every attempt; request data never selects a user.
// No request, upstream response, token, or personal data is logged.
export async function deleteAccount(request, env, fetcher = fetch) {
  const reply = (status, error) => new Response(
    error ? JSON.stringify({ error }) : null,
    { status, headers: { "Cache-Control": "no-store", "Content-Type": "application/json" } },
  );
  if (request.method !== "POST") return reply(405, "method_not_allowed");
  const authorization = request.headers.get("Authorization") || "";
  if (!/^Bearer [^\s]+$/i.test(authorization)) return reply(401, "unauthorized");
  if (new URL(request.url).search) return reply(400, "invalid_request");
  // A bounded, exact confirmation contract also rejects arbitrary user IDs.
  try {
    if (!request.headers.get("Content-Type")?.startsWith("application/json")) {
      return reply(400, "invalid_request");
    }
    const reader = request.body?.getReader();
    if (!reader) return reply(400, "invalid_request");
    const chunks = [];
    let length = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 256) {
        await reader.cancel();
        return reply(400, "invalid_request");
      }
      chunks.push(...value);
    }
    const body = JSON.parse(new TextDecoder().decode(new Uint8Array(chunks)));
    if (!body || Array.isArray(body) || Object.keys(body).length !== 1 ||
      body.confirmation !== "DELETE") return reply(400, "invalid_request");
  } catch {
    return reply(400, "invalid_request");
  }
  const url = env.SUPABASE_URL?.replace(/\/$/, "");
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return reply(503, "temporarily_unavailable");
  try {
    // Same Auth endpoint as auth.getUser(jwt): signature, expiry and live user
    // validation occur at Auth, not via locally decoded JWT claims.
    const verified = await fetcher(`${url}/auth/v1/user`, {
      headers: { apikey: key, Authorization: authorization },
      redirect: "error",
      signal: AbortSignal.timeout(10000),
    });
    if (!verified.ok) {
      return verified.status === 401 || verified.status === 403
        ? reply(401, "unauthorized") : reply(503, "temporarily_unavailable");
    }
    const user = await verified.json();
    if (user.role !== "authenticated" || user.is_anonymous !== false ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(user.id)) {
      return reply(401, "unauthorized");
    }
    const deleted = await fetcher(`${url}/auth/v1/admin/users/${user.id}`, {
      method: "DELETE",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ should_soft_delete: false }),
      redirect: "error",
      signal: AbortSignal.timeout(15000),
    });
    // A concurrent delete after successful authentication is already complete.
    if (deleted.ok || deleted.status === 404) return reply(204);
    return reply(503, "temporarily_unavailable");
  } catch {
    // A lost response is ambiguous: retry safely; never claim it was rolled back.
    return reply(503, "temporarily_unavailable");
  }
}
