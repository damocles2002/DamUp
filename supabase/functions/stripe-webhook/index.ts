// ============================================================
//  DamUp — Edge Function "stripe-webhook"
//  Signature Stripe obligatoire (STRIPE_WEBHOOK_SECRET).
// ============================================================
import Stripe from "npm:stripe@14";
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  if (!signature) return new Response("Missing signature", { status: 400 });
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", { apiVersion: "2023-10-16" });
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  let event;
  try {
    const body = await req.text();
    event = await stripe.webhooks.constructEventAsync(body, signature, secret);
  } catch (e) {
    return new Response("Invalid signature", { status: 400 });
  }

  try {
    const obj = event.data.object as any;

    if (event.type === "invoice.paid") {
      const customerId = obj.customer;
      if (customerId) {
        const { data: prof } = await admin.from("profiles").select("id, periode").eq("stripe_customer_id", customerId).single();
        if (prof?.id) {
          const mode = obj.payment_intent?.payment_method_types?.includes("sepa_debit") ? "prelevement" : "carte";
          const montant = obj.amount_paid / 100;
          await admin.rpc("prolonger_abonnement", {
            p_profil: prof.id, p_montant: montant, p_mode: mode,
            p_periode: prof.periode || "mensuel", p_date: new Date().toISOString(),
            p_ref: obj.id, p_note: null,
          });
        }
      }
    } else if (event.type === "checkout.session.completed") {
      // prélèvement SEPA : délai de grâce de 7 jours (confirmation lente)
      if (obj.payment_method_types?.includes("sepa_debit")) {
        const profilId = obj.metadata?.profil_id;
        if (profilId) {
          const { data: prof } = await admin.from("profiles").select("actif_jusqu_a").eq("id", profilId).single();
          const grace = new Date(Math.max(new Date(prof?.actif_jusqu_a || 0).getTime(), Date.now() + 7 * 86400000)).toISOString();
          await admin.from("profiles").update({ actif_jusqu_a: grace }).eq("id", profilId);
        }
      }
    } else if (event.type === "invoice.payment_failed") {
      const email = obj.customer_email;
      if (email) {
        const { data: prof } = await admin.from("profiles").select("id").eq("email", email).single();
        if (prof?.id) {
          await admin.from("notifications").insert({ user_id: prof.id, message: "⚠️ Ton paiement n'est pas passé, mets à jour ton moyen de paiement." });
        }
      }
    } else if (event.type === "charge.dispute.created") {
      const { data: admins } = await admin.from("profiles").select("id").eq("type", "admin");
      for (const a of admins || []) {
        await admin.from("notifications").insert({ user_id: a.id, message: "⚠️ Contestation Stripe détectée. Consulte ton tableau de bord Stripe." });
      }
    }

    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response("error", { status: 200 });
  }
});
