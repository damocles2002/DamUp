// ============================================================
//  DamUp — Edge Function "notifier"
//  Envoie un e-mail (via Resend) après vérification de l'auth.
//  Utilisé pour : acceptation/refus d'une candidature,
//  nouvelle mission, décision de l'administrateur.
// ============================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM = Deno.env.get("FROM_EMAIL") ?? "DamUp <onboarding@resend.dev>";

serve(async (req) => {
  try {
    // 1) Vérifier que l'appelant est bien connecté (sécurité)
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401 });
    }

    // 2) Envoyer l'e-mail
    const { to, subject, html } = await req.json();
    if (!to || !subject) {
      return new Response(JSON.stringify({ error: "to et subject requis" }), { status: 400 });
    }

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ from: FROM, to: [to], subject, html }),
    });

    const body = await res.json();
    return new Response(JSON.stringify({ ok: res.ok, id: body.id }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 500 });
  }
});
