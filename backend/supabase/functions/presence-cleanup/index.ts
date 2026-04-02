import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve(async () => {
  if (!supabaseUrl || !serviceRoleKey) {
    return json(
      {
        ok: false,
        error: "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be configured.",
      },
      500,
    );
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const { data, error } = await client.rpc("cleanup_backend_state");

  if (error) {
    return json({ ok: false, error: error.message }, 500);
  }

  return json({ ok: true, result: data });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}
