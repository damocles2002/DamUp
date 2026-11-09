// ============================================================
//  DamUp : Edge Function "connexion" (S5 - alertes de connexion)
//  Journalise la connexion d'un membre + alerte le propriétaire
//  sur un nouvel appareil. Accepte aal1 (appelé dès le login).
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SENDER_EMAIL = Deno.env.get("SENDER_EMAIL") ?? "";

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

function simplifierUA(ua: string): string {
  const s = ua || "";
  let nav = "Navigateur inconnu";
  if (s.includes("Edg/")) nav = "Microsoft Edge";
  else if (s.includes("Chrome/")) nav = "Chrome";
  else if (s.includes("Safari/") && !s.includes("Chrome")) nav = "Safari";
  else if (s.includes("Firefox/")) nav = "Firefox";
  let os = "appareil inconnu";
  if (s.includes("Android")) os = "Android";
  else if (s.includes("iPhone") || s.includes("iPad")) os = "iOS";
  else if (s.includes("Windows")) os = "Windows";
  else if (s.includes("Mac OS")) os = "macOS";
  else if (s.includes("Linux")) os = "Linux";
  return nav + " sur " + os;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json(req, { error: "Non authentifié" }, 401);

    const { data: membre } = await admin.from("equipe").select("*").eq("user_id", user.id).single();
    if (!membre || membre.suspendu) return json(req, { error: "Pas un membre actif" }, 403);

    const body = await req.json() as any;
    const appareil = String(body?.appareil || "inconnu");
    const navigateur = simplifierUA(req.headers.get("user-agent") ?? "");

    // journaliser la connexion
    await admin.from("journal_admin").insert({
      auteur_id: user.id, action: "connexion", cible_type: "equipe", cible_id: membre.id,
      details: { appareil, navigateur },
    });

    // nouvel appareil ?
    const { data: existant } = await admin.from("connexions_admin").select("id").eq("user_id", user.id).eq("appareil", appareil).limit(1);
    const estNouveau = !(existant && existant.length);
    if (estNouveau) {
      await admin.from("connexions_admin").insert({ user_id: user.id, appareil, navigateur });
      const membreEmail = user.email ?? "";
      let proprioEmail = "";
      const { data: proprio } = await admin.from("equipe").select("user_id").eq("proprietaire", true).single();
      if (proprio?.user_id) {
        const { data: pu } = await admin.auth.admin.getUserById(proprio.user_id);
        proprioEmail = pu?.user?.email ?? "";
      }
      const date = new Date().toLocaleString("fr-FR");
      const sujet = `Nouvelle connexion au back-office DamUp : ${membre.nom}, ${navigateur}, ${date}`;
      const corps = `<p>Nouvelle connexion au back-office DamUp : <b>${membre.nom}</b>, ${navigateur}, ${date}.</p><p>Si ce n'est pas normal, suspends ce compte.</p>`;
      if (SENDER_EMAIL) {
        const destinataires = [...new Set([proprioEmail, membreEmail].filter(Boolean))];
        for (const to of destinataires) {
          await fetch("https://api.brevo.com/v3/smtp/email", {
            method: "POST",
            headers: { "Content-Type": "application/json", "api-key": BREVO_API_KEY },
            body: JSON.stringify({ sender: { name: "DamUp", email: SENDER_EMAIL }, to: [{ email: to }], subject: sujet, htmlContent: corps }),
          });
        }
      }
    }
    return json(req, { ok: true, nouveau: estNouveau });
  } catch (e) {
    return json(req, { error: (e as Error).message }, 500);
  }
});
