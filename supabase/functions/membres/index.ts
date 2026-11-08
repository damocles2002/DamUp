// ============================================================
//  DamUp : Edge Function "membres" (gestion de l'équipe admin)
//  Permet à l'ADMIN de créer/modifier/supprimer des comptes
//  membres et de leur donner des droits, SANS toucher au code.
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGINES = ["https://damup.fr", "https://www.damup.fr", "https://damocles2002.github.io"];
function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGINES.includes(origin) ? origin : ORIGINES[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}


const json = (req: Request, data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // 1) Vérifier que l'appelant est bien un administrateur
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json(req, { error: "Non authentifié" }, 401);
    const { data: prof } = await admin.from("profiles").select("type").eq("id", user.id).single();
    if (!prof || prof.type !== "admin") return json(req, { error: "Accès réservé à l'administrateur" }, 403);

    const body = await req.json(req, );
    const { action } = body;

    // ---- lister les membres ----
    if (action === "list") {
      const { data, error } = await admin.from("equipe").select("*").order("created_at");
      return json(req, { data, error: error?.message });
    }

    // ---- créer un membre (compte auth + équipe) ----
    // Le profil admin est créé par le déclencheur handle_new_user,
    // grâce à app_metadata.role = "admin" (B1) : pas d'insertion manuelle.
    if (action === "create") {
      const { email, password, nom, droits } = body;
      if (!email || !password) return json(req, { error: "E-mail et mot de passe requis" }, 400);
      const { data: created, error: err } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: { role: "admin" },
      });
      if (err) return json(req, { error: err.message }, 400);
      const { error: err2 } = await admin.from("equipe").insert({
        user_id: created.user.id, nom, role: "membre", droits: droits || {},
      });
      if (err2) return json(req, { error: err2.message }, 400);
      return json(req, { ok: true, id: created.user.id });
    }

    // ---- modifier les droits d'un membre ----
    if (action === "update") {
      const { id, nom, droits } = body;
      const { error } = await admin.from("equipe").update({ nom, droits }).eq("id", id);
      return json(req, { ok: !error, error: error?.message });
    }

    // ---- supprimer un membre (compte auth + équipe) ----
    if (action === "delete") {
      const { id, user_id } = body;
      if (user_id) await admin.auth.admin.deleteUser(user_id);
      await admin.from("equipe").delete().eq("id", id);
      return json(req, { ok: true });
    }

    return json(req, { error: "Action inconnue" }, 400);
  } catch (e) {
    return json(req, { error: (e as Error).message }, 500);
  }
});
