// ============================================================
//  DamUp — Edge Function "membres" (gestion de l'équipe admin)
//  Permet à l'ADMIN de créer/modifier/supprimer des comptes
//  membres et de leur donner des droits, SANS toucher au code.
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "https://damocles2002.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // 1) Vérifier que l'appelant est bien un administrateur
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: "Non authentifié" }, 401);
    const { data: prof } = await admin.from("profiles").select("type").eq("id", user.id).single();
    if (!prof || prof.type !== "admin") return json({ error: "Accès réservé à l'administrateur" }, 403);

    const body = await req.json();
    const { action } = body;

    // ---- lister les membres ----
    if (action === "list") {
      const { data, error } = await admin.from("equipe").select("*").order("created_at");
      return json({ data, error: error?.message });
    }

    // ---- créer un membre (compte auth + équipe) ----
    // Le profil admin est créé par le déclencheur handle_new_user,
    // grâce à app_metadata.role = "admin" (B1) — pas d'insertion manuelle.
    if (action === "create") {
      const { email, password, nom, droits } = body;
      if (!email || !password) return json({ error: "E-mail et mot de passe requis" }, 400);
      const { data: created, error: err } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: { role: "admin" },
      });
      if (err) return json({ error: err.message }, 400);
      const { error: err2 } = await admin.from("equipe").insert({
        user_id: created.user.id, nom, role: "membre", droits: droits || {},
      });
      if (err2) return json({ error: err2.message }, 400);
      return json({ ok: true, id: created.user.id });
    }

    // ---- modifier les droits d'un membre ----
    if (action === "update") {
      const { id, nom, droits } = body;
      const { error } = await admin.from("equipe").update({ nom, droits }).eq("id", id);
      return json({ ok: !error, error: error?.message });
    }

    // ---- supprimer un membre (compte auth + équipe) ----
    if (action === "delete") {
      const { id, user_id } = body;
      if (user_id) await admin.auth.admin.deleteUser(user_id);
      await admin.from("equipe").delete().eq("id", id);
      return json({ ok: true });
    }

    return json({ error: "Action inconnue" }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
