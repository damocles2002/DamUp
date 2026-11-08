// ============================================================
//  DamUp — Edge Function "facture-envoyer"
//  Protégée par le secret partagé (x-damup-secret).
//  Génère le PDF de la facture (pdf-lib), l'enregistre dans le
//  bucket privé "factures", puis l'envoie par Brevo en pièce jointe.
// ============================================================
import { PDFDocument, rgb } from "npm:pdf-lib@1.17.1";
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "https://damocles2002.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-damup-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const AUBERGINE = rgb(0.165, 0.067, 0.125); // #2A1120
const CHAMPAGNE = rgb(0.906, 0.812, 0.659); // #E7CFA8
const GRIS = rgb(0.4, 0.4, 0.4);

function bytesToBase64(bytes: Uint8Array): string {
  let b = "";
  for (let i = 0; i < bytes.length; i++) b += String.fromCharCode(bytes[i]);
  return btoa(b);
}

function fmtDate(d: string | null): string {
  if (!d) return "";
  return new Date(d).toLocaleDateString("fr-FR");
}

async function genererPdf(f: any): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([595, 842]); // A4 portrait
  const { width, height } = page.getSize();
  const helv = await doc.embedFont("Helvetica");
  const helvBold = await doc.embedFont("Helvetica-Bold");

  const estAvoir = f.type === "avoir";
  const titre = estAvoir ? "AVOIR" : "FACTURE";

  // bandeau aubergine
  page.drawRectangle({ x: 0, y: height - 120, width, height: 120, color: AUBERGINE });
  page.drawText("DAMUP", { x: 48, y: height - 60, size: 26, font: helvBold, color: CHAMPAGNE });
  page.drawText(titre + "  " + (f.numero || ""), { x: 48, y: height - 88, size: 16, font: helvBold, color: rgb(1, 1, 1) });
  page.drawText("Émise le " + fmtDate(f.date_emission), { x: width - 260, y: height - 88, size: 10, font: helv, color: rgb(1, 1, 1) });

  let y = height - 160;

  // vendeur (gauche)
  page.drawText("Émetteur", { x: 48, y, size: 9, font: helvBold, color: GRIS });
  y -= 16;
  const v = f.vendeur || {};
  page.drawText(v.nom || "", { x: 48, y, size: 11, font: helvBold, color: AUBERGINE });
  y -= 15;
  page.drawText("Entrepreneur individuel", { x: 48, y, size: 10, font: helv, color: AUBERGINE });
  y -= 14;
  page.drawText(v.adresse || "", { x: 48, y, size: 10, font: helv, color: AUBERGINE });
  y -= 14;
  page.drawText("SIRET : " + (v.siret || ""), { x: 48, y, size: 10, font: helv, color: AUBERGINE });

  // client (droite)
  let cy = height - 160;
  const c = f.client || {};
  page.drawText("Client", { x: width - 260, y: cy, size: 9, font: helvBold, color: GRIS });
  cy -= 16;
  page.drawText(c.nom || "", { x: width - 260, y: cy, size: 11, font: helvBold, color: AUBERGINE });
  cy -= 15;
  page.drawText(c.adresse || "", { x: width - 260, y: cy, size: 10, font: helv, color: AUBERGINE });
  cy -= 14;
  page.drawText("SIRET : " + (c.siret || ""), { x: width - 260, y: cy, size: 10, font: helv, color: AUBERGINE });

  // table
  y -= 40;
  page.drawRectangle({ x: 48, y: y - 20, width: width - 96, height: 24, color: CHAMPAGNE });
  page.drawText("Désignation", { x: 56, y: y - 13, size: 9, font: helvBold, color: AUBERGINE });
  page.drawText("Qté", { x: 380, y: y - 13, size: 9, font: helvBold, color: AUBERGINE });
  page.drawText("P.U. HT", { x: 420, y: y - 13, size: 9, font: helvBold, color: AUBERGINE });
  page.drawText("Total", { x: 490, y: y - 13, size: 9, font: helvBold, color: AUBERGINE });
  y -= 34;

  const lignes = f.lignes || [];
  for (const l of lignes) {
    page.drawText(l.designation || "", { x: 56, y, size: 9, font: helv, color: AUBERGINE });
    page.drawText(String(l.quantite ?? 1), { x: 380, y, size: 9, font: helv, color: AUBERGINE });
    page.drawText(Number(l.prix_unitaire || 0).toFixed(2) + " €", { x: 420, y, size: 9, font: helv, color: AUBERGINE });
    page.drawText(Number(l.total || 0).toFixed(2) + " €", { x: 490, y, size: 9, font: helv, color: AUBERGINE });
    y -= 18;
  }

  // total
  y -= 10;
  page.drawText("Total " + (estAvoir ? "de l'avoir" : "HT") + " : " + Number(f.total || 0).toFixed(2) + " €", { x: width - 260, y, size: 12, font: helvBold, color: AUBERGINE });
  y -= 16;
  page.drawText((v.mention_tva || ""), { x: 48, y, size: 9, font: helv, color: GRIS });
  y -= 26;

  // paiement / acquittée
  const modes: Record<string, string> = { especes: "espèces", carte: "carte bancaire", prelevement: "prélèvement SEPA" };
  if (f.acquittee_le) {
    page.drawText("Facture acquittée le " + fmtDate(f.acquittee_le) + " par " + (modes[f.mode_paiement] || f.mode_paiement || ""), { x: 48, y, size: 9, font: helv, color: AUBERGINE });
    y -= 14;
  }
  if (estAvoir && f.facture_origine) {
    page.drawText("Avoir sur la facture d'origine", { x: 48, y, size: 9, font: helvBold, color: AUBERGINE });
    y -= 14;
  }
  y -= 6;
  page.drawText("Pénalités de retard : trois fois le taux d'intérêt légal. Indemnité forfaitaire pour frais de recouvrement : 40 €. Pas d'escompte pour paiement anticipé.", { x: 48, y, size: 8, font: helv, color: GRIS });

  return await doc.save();
}

async function envoyerBrevo(f: any, pdf: Uint8Array, admin: any) {
  const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
  const SENDER_EMAIL = Deno.env.get("SENDER_EMAIL") ?? "";
  const c = f.client || {};
  const dest = c.email || "";
  if (!dest) throw new Error("Adresse e-mail du client introuvable");

  // copie cachée pour l'archive (e-mail de contact DamUp)
  let bcc: { email: string }[] = [];
  try {
    const { data: s } = await admin.from("settings").select("value").eq("key", "contact_email").single();
    const cc = (s && s.value || "").trim();
    if (cc) bcc = [{ email: cc }];
  } catch (e) { /* ignore */ }

  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "Content-Type": "application/json", "api-key": BREVO_API_KEY },
    body: JSON.stringify({
      sender: { name: "DamUp", email: SENDER_EMAIL },
      to: [{ email: dest }],
      bcc,
      subject: "Votre facture DamUp n° " + (f.numero || ""),
      htmlContent: "<p>Bonjour,</p><p>Veuillez trouver en pièce jointe votre facture DamUp n° <b>" + (f.numero || "") + "</b>.</p><p>Merci de votre confiance,<br>L'équipe DamUp</p>",
      attachment: [{ name: (f.numero || "facture") + ".pdf", content: bytesToBase64(pdf) }],
    }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error("Brevo: " + text.slice(0, 200));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const secret = req.headers.get("x-damup-secret") ?? "";
    const attendu = Deno.env.get("NOTIFIER_SECRET") ?? "";
    if (!attendu || secret !== attendu) return json({ error: "Non autorisé" }, 401);

    const { facture_id } = await req.json();
    if (!facture_id) return json({ error: "facture_id requis" }, 400);

    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: f, error } = await admin.from("factures").select("*").eq("id", facture_id).single();
    if (error || !f) return json({ error: "Facture introuvable" }, 404);

    const pdf = await genererPdf(f);

    // enregistre le PDF dans le bucket privé
    const path = f.profil_id + "/" + f.numero + ".pdf";
    const { error: upErr } = await admin.storage.from("factures").upload(path, pdf, { contentType: "application/pdf", upsert: true });
    if (upErr) throw new Error("upload: " + upErr.message);
    await admin.from("factures").update({ pdf_chemin: path }).eq("id", facture_id);

    await envoyerBrevo(f, pdf, admin);
    await admin.from("factures").update({ envoyee_le: new Date().toISOString(), envoi_erreur: null }).eq("id", facture_id);

    return json({ ok: true });
  } catch (e) {
    return json({ ok: false, error: (e as Error).message }, 500);
  }
});
