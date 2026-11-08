// ============================================================
//  DamUp : Edge Function "paiement-portail" (portail client Stripe)
// ============================================================
import Stripe from "npm:stripe@14";
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

    const { data: profil } = await admin.from("profiles").select("stripe_customer_id, stripe_compte").eq("id", user.id).single();
    if (!profil?.stripe_customer_id || profil.stripe_compte !== (Deno.env.get("STRIPE_COMPTE") ?? "")) {
      return json(req, { error: "Aucun paiement en ligne en cours." }, 400);
    }
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2023-10-16" });
    const session = await stripe.billingPortal.sessions.create({ customer: profil.stripe_customer_id });
    return json(req, { url: session.url });
  } catch (e) {
    return json(req, { error: (e as Error).message }, 500);
  }
});
