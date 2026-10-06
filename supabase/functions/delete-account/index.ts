import { deleteAccount } from "./handler.js";

Deno.serve((request: Request) => deleteAccount(request, {
  SUPABASE_URL: Deno.env.get("SUPABASE_URL"),
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
}));
