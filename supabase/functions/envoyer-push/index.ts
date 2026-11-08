// ============================================================
//  DamUp : Edge Function "envoyer-push"
//  Protégée par le secret partagé (x-damup-secret).
//  Envoie une notification push à tous les appareils de l'utilisateur.
//  Supprime les abonnements expirés (404/410).
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const CORS = {
  "Access-Control-Allow-Origin": "https://damocles2002.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-damup-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const secret = req.headers.get("x-damup-secret") ?? "";
    const attendu = Deno.env.get("NOTIFIER_SECRET") ?? "";
    if (!attendu || secret !== attendu) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: { ...CORS, "Content-Type": "application/json" } });
    }

    const { user_id, titre, texte, url } = await req.json();
    if (!user_id || !texte) return new Response(JSON.stringify({ error: "paramètres requis" }), { status: 400, headers: { ...CORS, "Content-Type": "application/json" } });

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: appareils } = await supabase.from("appareils_push").select("*").eq("user_id", user_id);

    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUJET")!,
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!
    );

    const payload = JSON.stringify({ titre: titre || "DamUp", texte, url: url || "" });

    let envoyes = 0;
    for (const a of (appareils || [])) {
      try {
        await webpush.sendNotification({ endpoint: a.endpoint, keys: { p256dh: a.p256dh, auth: a.auth_cle } }, payload);
        envoyes++;
      } catch (e: any) {
        if (e?.statusCode === 404 || e?.statusCode === 410) {
          await supabase.from("appareils_push").delete().eq("id", a.id);
        }
      }
    }
    return new Response(JSON.stringify({ ok: true, envoyes }), { status: 200, headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: (e as Error).message }), { status: 500, headers: { ...CORS, "Content-Type": "application/json" } });
  }
});
