// ============================================================
//  DamUp : Edge Function "verifier-siret"
//  Interroge l'annuaire officiel des entreprises (API publique
//  et gratuite) pour contrôler un SIRET. Réservée aux membres
//  de l'équipe (aal2 + droit valider_profils, ou propriétaire).
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

const json = (req: Request, data: unknown, status = 200): Response =>
  new Response(JSON.stringify(data), { status, headers: { ...corsHeaders(req), "Content-Type": "application/json" } });

function decodeJwt(token: string): Record<string, unknown> {
  const payload = token.split(".")[1];
  return JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json(req, { erreur: "Non connecté." }, 401);

    // double vérification obligatoire (aal2)
    try {
      const claims = decodeJwt(authHeader.replace(/^Bearer\s+/i, ""));
      if (claims.aal !== "aal2") return json(req, { erreur: "Double vérification requise" }, 403);
    } catch {
      return json(req, { erreur: "Jeton invalide" }, 401);
    }

    // membre actif de l'équipe + droit valider_profils (ou propriétaire)
    const { data: membre } = await admin.from("equipe").select("*").eq("user_id", user.id).single();
    if (!membre || membre.suspendu) return json(req, { erreur: "Réservé à l'équipe" }, 403);
    const aDroit = membre.proprietaire === true || (membre.droits?.valider_profils === true);
    if (!aDroit) return json(req, { erreur: "Droit insuffisant" }, 403);

    let siret = "";
    try {
      const body = await req.json() as any;
      siret = (body?.siret ?? "").toString();
    } catch (_) {
      siret = new URL(req.url).searchParams.get("siret") ?? "";
    }
    const clean = siret.replace(/[^0-9]/g, "");
    if (clean.length !== 14) return json(req, { introuvable: true, motif: "SIRET invalide (14 chiffres attendus)." });

    const r = await fetch(
      `https://recherche-entreprises.api.gouv.fr/search?q=${encodeURIComponent(clean)}&per_page=1`,
    );
    if (!r.ok) return json(req, { erreur: "Annuaire indisponible, réessaie plus tard." }, 502);
    const data = await r.json() as any;
    const entreprise = data?.results?.[0];
    if (!entreprise) return json(req, { introuvable: true });

    const siege = entreprise.siege ?? {};
    const adresse = [
      siege.adresse ?? "",
      siege.code_postal ?? "",
      siege.ville ?? siege.libelle_commune ?? "",
    ].filter(Boolean).join(", ");

    return json(req, {
      introuvable: false,
      nom_officiel: entreprise.nom_complet || entreprise.nom_raison_sociale || "",
      adresse,
      activite: entreprise.activite_principale || entreprise.libelle_activite_principale || "",
      etat: entreprise.etat_administratif === "A" ? "active" : "fermee",
    });
  } catch (e) {
    return json(req, { erreur: (e as Error).message }, 500);
  }
});
