// ============================================================
//  DamUp : Edge Function "notifier" (envoi d'emails via Brevo)
//  Fermée au public (B6) : exige l'en-tête x-damup-secret.
// ============================================================

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SENDER_EMAIL = Deno.env.get("SENDER_EMAIL") ?? "";
const SENDER_NAME = "DamUp";

const CORS = {
  "Access-Control-Allow-Origin": "https://damocles2002.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-damup-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    // Secret partagé obligatoire : seul le déclencheur SQL (qui connaît le secret)
    // peut envoyer un email au nom de DamUp.
    const secret = req.headers.get("x-damup-secret") ?? "";
    const attendu = Deno.env.get("NOTIFIER_SECRET") ?? "";
    if (!attendu || secret !== attendu) {
      return json({ error: "Non autorisé" }, 401);
    }

    const { to, subject, html } = await req.json();
    if (!to || !subject) return json({ error: "to et subject requis" }, 400);
    if (!SENDER_EMAIL) return json({ error: "Expéditeur non configuré" }, 500);

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
    return json({ ok: res.ok, message: res.ok ? "envoyé" : text });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
