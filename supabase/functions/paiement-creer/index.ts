// ============================================================
//  DamUp : Edge Function "paiement-creer" (Stripe Checkout)
//  Appelée par l'utilisateur connecté. CORS comme les autres.
// ============================================================
import Stripe from "npm:stripe@14";
import { createClient } from "npm:@supabase/supabase-js@2";

const SITE_URL = "https://damup.fr";
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
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json(req, { error: "Non authentifié" }, 401);

    const { data: reglages } = await admin.from("settings").select("value").eq("key", "paiement_en_ligne_actif").single();
    if (!reglages || reglages.value !== "true") return json(req, { error: "Paiement en ligne désactivé." }, 400);

    const { data: profil } = await admin.from("profiles").select("tarif, periode, stripe_customer_id, stripe_compte, email").eq("id", user.id).single();
    if (!profil || !profil.tarif) return json(req, { error: "Aucun tarif défini. Contacte DamUp." }, 400);

    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2023-10-16" });
    const compte = Deno.env.get("STRIPE_COMPTE") ?? "";

    let customerId = profil.stripe_customer_id;
    if (!customerId || profil.stripe_compte !== compte) {
      const { data: nomEtab } = await admin.from("etablissements").select("nom").eq("id", user.id).single();
      const customer = await stripe.customers.create({
        email: profil.email,
        name: nomEtab?.nom || undefined,
        metadata: { profil_id: user.id },
      });
      customerId = customer.id;
      await admin.from("profiles").update({ stripe_customer_id: customerId, stripe_compte: compte }).eq("id", user.id);
    }

    const interval = profil.periode === "hebdomadaire" ? "week" : "month";
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      locale: "fr",
      payment_method_types: ["card", "sepa_debit"],
      line_items: [{
        quantity: 1,
        price_data: {
          currency: "eur",
          unit_amount: Math.round(Number(profil.tarif) * 100),
          recurring: { interval },
          product_data: { name: "Abonnement DamUp" },
        },
      }],
      metadata: { profil_id: user.id },
      subscription_data: { metadata: { profil_id: user.id } },
      success_url: SITE_URL + "/etablissement.html?paiement=ok",
      cancel_url: SITE_URL + "/etablissement.html?paiement=annule",
    });
    return json(req, { url: session.url });
  } catch (e) {
    return json(req, { error: (e as Error).message }, 500);
  }
});
