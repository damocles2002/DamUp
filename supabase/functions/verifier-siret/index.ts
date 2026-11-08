// ============================================================
//  DamUp : Edge Function "verifier-siret"
//  Interroge l'annuaire officiel des entreprises (API publique
//  et gratuite) pour contrôler un SIRET. Réservée à l'admin.
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabase = createClient(url, anon, {
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ erreur: "Non connecté." }, 401);

  const { data: p } = await supabase.from("profiles").select("type").eq("id", user.id).single();
  if (p?.type !== "admin") return json({ erreur: "Réservé à l'administrateur." }, 403);

  let siret = "";
  try {
    const body = await req.json();
    siret = (body?.siret ?? "").toString();
  } catch (_) {
    siret = new URL(req.url).searchParams.get("siret") ?? "";
  }
  const clean = siret.replace(/[^0-9]/g, "");
  if (clean.length !== 14) return json({ introuvable: true, motif: "SIRET invalide (14 chiffres attendus)." });

  try {
    const r = await fetch(
      `https://recherche-entreprises.api.gouv.fr/search?q=${encodeURIComponent(clean)}&per_page=1`,
    );
    if (!r.ok) return json({ erreur: "Annuaire indisponible, réessaie plus tard." }, 502);
    const data = await r.json();
    const entreprise = data?.results?.[0];
    if (!entreprise) return json({ introuvable: true });

    const siege = entreprise.siege ?? {};
    const adresse = [
      siege.adresse ?? "",
      siege.code_postal ?? "",
      siege.ville ?? siege.libelle_commune ?? "",
    ].filter(Boolean).join(", ");

    return json({
      introuvable: false,
      nom_officiel: entreprise.nom_complet || entreprise.nom_raison_sociale || "",
      adresse,
      activite: entreprise.activite_principale || entreprise.libelle_activite_principale || "",
      etat: entreprise.etat_administratif === "A" ? "active" : "fermee",
    });
  } catch (_) {
    return json({ erreur: "Impossible d'interroger l'annuaire officiel." }, 502);
  }
});
