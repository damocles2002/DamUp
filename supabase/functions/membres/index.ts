// ============================================================
//  DamUp — Edge Function "membres" (gestion de l'équipe admin)
//  Permet à l'ADMIN de créer/modifier/supprimer des comptes
//  membres et de leur donner des droits, SANS toucher au code.
//  Utilise la clé service_role (création de comptes auth).
// ============================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // 1) Vérifier que l'appelant est bien un administrateur
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: "Non authentifié" }), { status: 401 });
    }
    const { data: prof } = await admin.from("profiles").select("type").eq("id", user.id).single();
    if (!prof || prof.type !== "admin") {
      return new Response(JSON.stringify({ error: "Accès réservé à l'administrateur" }), { status: 403 });
    }

    const body = await req.json();
    const { action } = body;

    // ---- lister les membres ----
    if (action === "list") {
      const { data, error } = await admin.from("equipe").select("*").order("created_at");
      return new Response(JSON.stringify({ data, error: error?.message }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // ---- créer un membre (compte auth + profil + équipe) ----
    if (action === "create") {
      const { email, password, nom, droits } = body;
      if (!email || !password) {
        return new Response(JSON.stringify({ error: "E-mail et mot de passe requis" }), { status: 400 });
      }
      const { data: created, error: err } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, // pas de mail de confirmation
      });
      if (err) return new Response(JSON.stringify({ error: err.message }), { status: 400 });
      await admin.from("profiles").insert({ id: created.user.id, type: "admin", email });
      const { error: err2 } = await admin.from("equipe").insert({
        user_id: created.user.id, nom, role: "membre", droits: droits || {},
      });
      if (err2) return new Response(JSON.stringify({ error: err2.message }), { status: 400 });
      return new Response(JSON.stringify({ ok: true, id: created.user.id }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // ---- modifier les droits d'un membre ----
    if (action === "update") {
      const { id, nom, droits } = body;
      const { error } = await admin.from("equipe").update({ nom, droits }).eq("id", id);
      return new Response(JSON.stringify({ ok: !error, error: error?.message }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // ---- supprimer un membre (compte auth + équipe) ----
    if (action === "delete") {
      const { id, user_id } = body;
      if (user_id) await admin.auth.admin.deleteUser(user_id);
      await admin.from("equipe").delete().eq("id", id);
      return new Response(JSON.stringify({ ok: true }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "Action inconnue" }), { status: 400 });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 500 });
  }
});
