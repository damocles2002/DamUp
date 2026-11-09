// ============================================================
//  DamUp : Edge Function "membres" (gestion de l'équipe admin)
//  Droits réels vérifiés côté serveur. Journalise chaque action.
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const DROITS = [
  "valider_profils", "suspendre_utilisateurs", "gerer_missions", "signalements",
  "voir_donnees", "paiements", "voir_finances", "reglages", "voir_journal", "gerer_equipe",
];

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
  new Response(JSON.stringify(data), { status, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // 1) identifier l'appelant
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json(req, { error: "Non authentifié" }, 401);

    const { data: moi } = await admin.from("equipe").select("*").eq("user_id", user.id).single();
    if (!moi || moi.suspendu) return json(req, { error: "Membre inactif ou introuvable" }, 403);
    const mesDroits: Record<string, boolean> = (moi.droits ?? {}) as Record<string, boolean>;
    const jeSuisProprio = moi.proprietaire === true;
    const ai = (d: string) => jeSuisProprio || mesDroits[d] === true;

    const { action } = await req.json();
    const journal = (action: string, cible: string | null, cibleId: string | null, details: unknown) =>
      admin.rpc("journaliser", { p_action: action, p_cible_type: cible, p_cible_id: cibleId, p_details: details ?? {} });

    // ---- mes propres infos (droits + propriétaire) ----
    if (action === "moi") {
      return json({ data: { nom: moi.nom, proprietaire: moi.proprietaire, suspendu: moi.suspendu, droits: moi.droits ?? {} } });
    }

    // ---- lister l'équipe ----
    if (action === "list") {
      if (!ai("gerer_equipe")) return json(req, { error: "Droit insuffisant" }, 403);
      const { data: equipe, error } = await admin.from("equipe").select("*").order("created_at");
      if (error) return json(req, { error: error.message }, 400);
      const emails: Record<string, string> = {};
      const { data: users } = await admin.auth.admin.listUsers();
      for (const u of (users?.users ?? [])) if (u.id) emails[u.id] = u.email ?? "";
      return json(req, { data: (equipe ?? []).map(e => ({ ...e, email: emails[e.user_id] ?? "" })) });
    }

    // ---- créer un membre ----
    if (action === "create") {
      if (!ai("gerer_equipe")) return json(req, { error: "Droit insuffisant" }, 403);
      const { email, password, nom, droits } = await req.json() as any;
      if (!email || !password) return json(req, { error: "E-mail et mot de passe requis" }, 400);
      const demandes: string[] = Object.keys((droits ?? {})).filter(k => (droits[k] === true));
      // droits = sous-ensemble des miens ; gerer_equipe réservé au propriétaire
      if (!jeSuisProprio) {
        if (demandes.includes("gerer_equipe")) return json(req, { error: "Seul le propriétaire peut accorder ce droit" }, 403);
        if (demandes.some(d => !DROITS.includes(d) || mesDroits[d] !== true)) return json(req, { error: "Tu ne peux pas accorder un droit que tu n'as pas" }, 403);
      }
      const { data: created, error: err } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, app_metadata: { role: "admin" },
      });
      if (err) return json(req, { error: err.message }, 400);
      const { error: err2 } = await admin.from("equipe").insert({
        user_id: created.user.id, nom, role: "membre", droits: droits ?? {}, proprietaire: false,
      });
      if (err2) return json(req, { error: err2.message }, 400);
      await journal("membre_cree", "equipe", created.user.id, { email, nom, droits });
      return json(req, { ok: true, id: created.user.id });
    }

    // ---- modifier un membre ----
    if (action === "update") {
      if (!ai("gerer_equipe")) return json(req, { error: "Droit insuffisant" }, 403);
      const { id, nom, droits } = await req.json() as any;
      const { data: cible } = await admin.from("equipe").select("*").eq("id", id).single();
      if (!cible) return json(req, { error: "Membre introuvable" }, 404);
      if (cible.proprietaire) return json(req, { error: "Le propriétaire ne peut pas être modifié" }, 403);
      if (cible.user_id === user.id) return json(req, { error: "Tu ne peux pas te modifier toi-même" }, 403);
      if (!jeSuisProprio && (cible.droits?.gerer_equipe === true)) return json(req, { error: "Seul le propriétaire agit sur un membre gérant l'équipe" }, 403);
      const demandes: string[] = Object.keys((droits ?? {})).filter(k => (droits[k] === true));
      if (!jeSuisProprio) {
        if (demandes.includes("gerer_equipe")) return json(req, { error: "Seul le propriétaire peut accorder ce droit" }, 403);
        if (demandes.some(d => !DROITS.includes(d) || mesDroits[d] !== true)) return json(req, { error: "Tu ne peux pas accorder un droit que tu n'as pas" }, 403);
      }
      const { error } = await admin.from("equipe").update({ nom, droits }).eq("id", id);
      if (error) return json(req, { error: error.message }, 400);
      await journal("membre_modifie", "equipe", id, { nom, droits });
      return json(req, { ok: true });
    }

    // ---- suspendre / réactiver ----
    if (action === "suspend" || action === "reactivate") {
      if (!ai("gerer_equipe")) return json(req, { error: "Droit insuffisant" }, 403);
      const { id, motif } = await req.json() as any;
      const { data: cible } = await admin.from("equipe").select("*").eq("id", id).single();
      if (!cible) return json(req, { error: "Membre introuvable" }, 404);
      if (cible.proprietaire) return json(req, { error: "Le propriétaire ne peut pas être suspendu" }, 403);
      if (cible.user_id === user.id) return json(req, { error: "Tu ne peux pas agir sur toi-même" }, 403);
      if (!jeSuisProprio && (cible.droits?.gerer_equipe === true)) return json(req, { error: "Seul le propriétaire agit sur un membre gérant l'équipe" }, 403);
      if (action === "suspend" && !motif) return json(req, { error: "Motif obligatoire" }, 400);
      const suspendre = action === "suspend";
      await admin.from("equipe").update({ suspendu: suspendre }).eq("id", id);
      await admin.from("profiles").update({ suspendu: suspendre }).eq("id", cible.user_id);
      await admin.auth.admin.updateUserById(cible.user_id, { ban_duration: suspendre ? "876000h" : "none" });
      await journal(suspendre ? "membre_suspendu" : "membre_reactivé", "equipe", id, { motif });
      return json(req, { ok: true });
    }

    // ---- supprimer un membre ----
    if (action === "delete") {
      if (!ai("gerer_equipe")) return json(req, { error: "Droit insuffisant" }, 403);
      const { id } = await req.json() as any;
      const { data: cible } = await admin.from("equipe").select("*").eq("id", id).single();
      if (!cible) return json(req, { error: "Membre introuvable" }, 404);
      if (cible.proprietaire) return json(req, { error: "Le propriétaire ne peut pas être supprimé" }, 403);
      if (cible.user_id === user.id) return json(req, { error: "Tu ne peux pas te supprimer toi-même" }, 403);
      if (!jeSuisProprio && (cible.droits?.gerer_equipe === true)) return json(req, { error: "Seul le propriétaire agit sur un membre gérant l'équipe" }, 403);
      await admin.auth.admin.deleteUser(cible.user_id);
      await admin.from("equipe").delete().eq("id", id);
      await journal("membre_supprime", "equipe", id, { email: cible.user_id });
      return json(req, { ok: true });
    }

    // ---- détail d'un membre (propriétaire uniquement) ----
    if (action === "detail") {
      if (!jeSuisProprio) return json(req, { error: "Réservé au propriétaire" }, 403);
      const { id } = await req.json() as any;
      const { data: cible } = await admin.from("equipe").select("*").eq("id", id).single();
      if (!cible) return json(req, { error: "Membre introuvable" }, 404);
      const { data: authUser } = await admin.auth.admin.getUserById(cible.user_id);
      const au = authUser?.user ?? {};
      const { data: stats } = await admin.rpc("admin_stats_membre", { p_uid: cible.user_id });
      const { data: actions } = await admin.from("journal_admin").select("*").eq("auteur_id", cible.user_id).order("created_at", { ascending: false }).limit(20);
      return json(req, { data: { membre: cible, email: au.email ?? "", created_at: au.created_at ?? "", last_sign_in_at: au.last_sign_in_at ?? null, stats, actions } });
    }

    return json(req, { error: "Action inconnue" }, 400);
  } catch (e) {
    return json(req, { error: (e as Error).message }, 500);
  }
});
