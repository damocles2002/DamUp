// ============================================================
//  DamUp — Edge Function "notifier" (envoi d'emails via Brevo)
//  Même technologie que DAMAVIS. Expéditeur : « DamUp ».
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SENDER_EMAIL = Deno.env.get("SENDER_EMAIL") ?? "ngongangdjomo@gmail.com";
const SENDER_NAME = "DamUp";

Deno.serve(async (req) => {
  try {
    // Vérifier que l'appelant est connecté (sécurité)
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401 });

    const { to, subject, html } = await req.json();
    if (!to || !subject) return new Response(JSON.stringify({ error: "to et subject requis" }), { status: 400 });

    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "Content-Type": "application/json", "api-key": BREVO_API_KEY },
      body: JSON.stringify({
        sender: { name: SENDER_NAME, email: SENDER_EMAIL },
        to: [{ email: to }],
        subject,
        htmlContent: html,
      }),
    });
    const text = await res.text();
    return new Response(JSON.stringify({ ok: res.ok, message: res.ok ? "envoyé" : text }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 500 });
  }
});
