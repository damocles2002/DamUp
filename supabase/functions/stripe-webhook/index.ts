// ============================================================
//  DamUp — Edge Function "stripe-webhook"
//  Signature Stripe obligatoire (STRIPE_WEBHOOK_SECRET).
//  Corrigé : moyen de paiement réel, erreurs -> 500, admins prévenus.
//  Notifications localisées via notifier_utilisateur() (clés notif.*).
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

  const obj = event.data.object as any;

  async function profilParCustomer(customerId: string) {
    if (!customerId) return null;
    const { data } = await admin.from("profiles").select("id, periode").eq("stripe_customer_id", customerId).single();
    return data ?? null;
  }
  async function prevenirAdmins(cle: string, params: Record<string, string> = {}) {
    const { data: admins } = await admin.from("profiles").select("id").eq("type", "admin");
    for (const a of admins || []) {
      await admin.rpc("notifier_utilisateur", { p_user: a.id, p_cle: cle, p_params: params });
    }
  }
  // détermine le moyen de paiement réel d'un PaymentIntent (carte / sepa_debit)
  async function typePaiement(paymentIntentId: string): Promise<string> {
    try {
      const pi = await stripe.paymentIntents.retrieve(paymentIntentId);
      if (pi.payment_method) {
        const pm = await stripe.paymentMethods.retrieve(pi.payment_method as string);
        return pm.type === "sepa_debit" ? "prelevement" : "carte";
      }
      if (pi.payment_method_types?.length === 1 && pi.payment_method_types[0] === "sepa_debit") return "prelevement";
    } catch (e) { /* ignore */ }
    return "carte";
  }

  try {
    if (event.type === "invoice.paid") {
      // obj.payment_intent est un ID, pas un objet ; le récupérer via l'API pour
      // distinguer carte et prélèvement.
      const prof = await profilParCustomer(obj.customer);
      if (!prof) throw new Error("Profil introuvable pour la facture " + obj.id);
      let mode = "carte";
      if (obj.payment_intent) mode = await typePaiement(obj.payment_intent);
      const montant = obj.amount_paid / 100;
      const { error } = await admin.rpc("prolonger_abonnement", {
        p_profil: prof.id, p_montant: montant, p_mode: mode,
        p_periode: prof.periode || "mensuel", p_date: new Date().toISOString(),
        p_ref: obj.id, p_note: null,
      });
      if (error) throw new Error("prolonger_abonnement: " + error.message);

    } else if (event.type === "checkout.session.completed") {
      // délai de grâce SEPA seulement si l'abonnement utilise réellement sepa_debit
      const profilId = obj.metadata?.profil_id;
      const subscriptionId = obj.subscription;
      if (!profilId || !subscriptionId) return new Response("ok", { status: 200 });
      let sepa = false;
      try {
        const sub = await stripe.subscriptions.retrieve(subscriptionId);
        if (sub.default_payment_method) {
          const pm = await stripe.paymentMethods.retrieve(sub.default_payment_method as string);
          sepa = pm.type === "sepa_debit";
        } else if (obj.payment_method_types?.length === 1 && obj.payment_method_types[0] === "sepa_debit") {
          sepa = true;
        }
      } catch (e) { sepa = false; }
      if (sepa) {
        const { data: prof } = await admin.from("profiles").select("actif_jusqu_a").eq("id", profilId).single();
        const grace = new Date(Math.max(new Date(prof?.actif_jusqu_a || 0).getTime(), Date.now() + 7 * 86400000)).toISOString();
        const { error } = await admin.from("profiles").update({ actif_jusqu_a: grace }).eq("id", profilId);
        if (error) throw new Error("délai de grâce: " + error.message);
      }

    } else if (event.type === "invoice.payment_failed") {
      const prof = await profilParCustomer(obj.customer);
      if (prof) {
        const { error } = await admin.rpc("notifier_utilisateur", { p_user: prof.id, p_cle: "notif.paiement_echoue", p_params: {} });
        if (error) throw new Error("notification client: " + error.message);
      }
      await prevenirAdmins("notif.paiement_echoue_admin", { ref: obj.id });

    } else if (event.type === "charge.dispute.created") {
      await prevenirAdmins("notif.contestation_admin");
    }

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("stripe-webhook error:", (e as Error).message);
    return new Response("error: " + (e as Error).message, { status: 500 });
  }
});
