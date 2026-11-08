// ============================================================
//  DamUp : Edge Function "verifier-siret"
//  Interroge l'annuaire officiel des entreprises (API publique
//  et gratuite) pour contrôler un SIRET. Réservée à l'admin.
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


function json(req, req: Request, data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabase = createClient(url, anon, {
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json(req, { erreur: "Non connecté." }, 401);

  const { data: p } = await supabase.from("profiles").select("type").eq("id", user.id).single();
  if (p?.type !== "admin") return json(req, { erreur: "Réservé à l'administrateur." }, 403);

  let siret = "";
  try {
    const body = await req.json(req, );
    siret = (body?.siret ?? "").toString();
  } catch (_) {
    siret = new URL(req.url).searchParams.get("siret") ?? "";
  }
  const clean = siret.replace(/[^0-9]/g, "");
  if (clean.length !== 14) return json(req, { introuvable: true, motif: "SIRET invalide (14 chiffres attendus)." });

  try {
    const r = await fetch(
      `https://recherche-entreprises.api.gouv.fr/search?q=${encodeURIComponent(clean)}&per_page=1`,
    );
    if (!r.ok) return json(req, { erreur: "Annuaire indisponible, réessaie plus tard." }, 502);
    const data = await r.json(req, );
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
  } catch (_) {
    return json(req, { erreur: "Impossible d'interroger l'annuaire officiel." }, 502);
  }
});
