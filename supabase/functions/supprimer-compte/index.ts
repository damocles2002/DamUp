// ============================================================
//  DamUp : Edge Function "supprimer-compte"
//  Supprime définitivement un compte hôtesse ou établissement.
//  Droits réels vérifiés côté serveur (aal2 + équipe).
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SENDER_EMAIL = Deno.env.get("SENDER_EMAIL") ?? "";

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
    // exiger la double vérification (aal2)
    try {
      const token = authHeader.replace(/^Bearer\s+/i, "");
      const payload = token.split(".")[1];
      const claims = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
      if (claims.aal !== "aal2") return json(req, { error: "Double vérification requise" }, 403);
    } catch {
      return json(req, { error: "Jeton invalide" }, 401);
    }

    // 2) membre actif + droit
    const { data: moi } = await admin.from("equipe").select("droits, proprietaire, suspendu").eq("user_id", user.id).single();
    if (!moi || moi.suspendu) return json(req, { error: "Membre inactif ou introuvable" }, 403);
    const ai = (d: string) => moi.proprietaire === true || ((moi.droits ?? {}) as Record<string, boolean>)[d] === true;
    if (!ai("suspendre_utilisateurs")) return json(req, { error: "Droit insuffisant" }, 403);

    // 3) cible
    const { profil_id } = await req.json() as any;
    if (!profil_id) return json(req, { error: "profil_id requis" }, 400);
    const { data: profil } = await admin.from("profiles").select("id, type, email").eq("id", profil_id).single();
    if (!profil) return json(req, { error: "Compte introuvable" }, 404);
    if (profil.type === "admin") return json(req, { error: "On ne supprime pas un administrateur ici" }, 403);

    // 4) e-mail avant suppression via le modèle pro (le compte n'existera plus après)
    const email = profil.email ?? "";
    try {
      if (email) {
        let prenom = "";
        if (profil.type === "etablissement") {
          const { data: etab } = await admin.from("etablissements").select("responsable_nom, nom").eq("id", profil_id).single();
          prenom = etab?.responsable_nom || etab?.nom || "";
        } else {
          const { data: h } = await admin.from("hotesses").select("prenom").eq("id", profil_id).single();
          prenom = h?.prenom || "";
        }
        const role = profil.type === "etablissement" ? "etablissement" : "hotesse";
        await fetch(`${url}/functions/v1/email`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${Deno.env.get("SUPABASE_ANON_KEY")}`,
            "x-damup-secret": Deno.env.get("NOTIFIER_SECRET") ?? "",
          },
          body: JSON.stringify({ evenement: "suppression_damup", email, role, variables: { prenom, motif: "manquement aux conditions d'utilisation" } }),
        });
      }
    } catch { /* l'e-mail ne doit pas bloquer la suppression */ }

    // 5) suppression de l'utilisateur auth
    const { error: errAuth } = await admin.auth.admin.deleteUser(profil_id);
    if (errAuth) return json(req, { error: errAuth.message }, 400);

    // 6) nettoyage des données liées (pas de cascade automatique)
    await admin.from("notifications").delete().eq("user_id", profil_id);
    await admin.from("appareils_push").delete().eq("user_id", profil_id);
    await admin.from("preferences_notif").delete().eq("user_id", profil_id);
    if (profil.type === "etablissement") {
      const { data: missions } = await admin.from("missions").select("id").eq("etablissement_id", profil_id);
      for (const m of missions ?? []) {
        await admin.from("candidatures").delete().eq("mission_id", m.id);
        await admin.from("avis").delete().eq("mission_id", m.id);
      }
      await admin.from("missions").delete().eq("etablissement_id", profil_id);
      await admin.from("avis").delete().eq("etablissement_id", profil_id);
    } else {
      await admin.from("candidatures").delete().eq("hotesse_id", profil_id);
      await admin.from("avis").delete().eq("hotesse_id", profil_id);
    }
    await admin.from("hotesses").delete().eq("id", profil_id);
    await admin.from("etablissements").delete().eq("id", profil_id);
    await admin.from("profiles").delete().eq("id", profil_id);

    // 7) journal
    await admin.from("journal_admin").insert({
      auteur_id: user.id, action: "compte_supprime", cible_type: "profil", cible_id: profil_id,
      details: { type: profil.type, email },
    });

    return json(req, { ok: true });
  } catch (e) {
    return json(req, { error: (e as Error).message }, 500);
  }
});
