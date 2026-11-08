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
const BLANC = rgb(1, 1, 1);

function bytesToBase64(bytes: Uint8Array): string {
  let b = "";
  for (let i = 0; i < bytes.length; i++) b += String.fromCharCode(bytes[i]);
  return btoa(b);
}

function fmtDate(d: string | null): string {
  if (!d) return "";
  return new Date(d).toLocaleDateString("fr-FR");
}

// montant au format français : 59,00 €
function fmtMontant(v: number): string {
  return Number(v || 0).toLocaleString("fr-FR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €";
}

// retour à la ligne automatique selon une largeur en caractères
function decouper(texte: string, largeur: number): string[] {
  const mots = (texte || "").split(/\s+/).filter(Boolean);
  const lignes: string[] = [];
  let ligne = "";
  for (const m of mots) {
    const test = ligne ? ligne + " " + m : m;
    if (test.length > largeur) {
      if (ligne) lignes.push(ligne);
      ligne = m;
    } else {
      ligne = test;
    }
  }
  if (ligne) lignes.push(ligne);
  return lignes;
}

async function genererPdf(f: any, factureOrigineNumero: string | null, contactEmail: string): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([595, 842]); // A4 portrait
  const { width, height } = page.getSize();
  const helv = await doc.embedFont("Helvetica");
  const helvBold = await doc.embedFont("Helvetica-Bold");

  const estAvoir = f.type === "avoir";
  const titre = estAvoir ? "AVOIR" : "FACTURE";

  // logo couronne (si récupérable)
  let logo: any = null;
  try {
    const r = await fetch("https://damocles2002.github.io/DamUp/assets/logo-couronne.png");
    if (r.ok) {
      const buf = await r.arrayBuffer();
      logo = await doc.embedPng(buf);
    }
  } catch (e) { /* sans logo */ }

  // bandeau aubergine
  page.drawRectangle({ x: 0, y: height - 120, width, height: 120, color: AUBERGINE });
  if (logo) {
    page.drawImage(logo, { x: 40, y: height - 92, width: 52, height: 52 });
    page.drawText("DAMUP", { x: 102, y: height - 72, size: 26, font: helvBold, color: CHAMPAGNE });
  } else {
    page.drawText("DAMUP", { x: 48, y: height - 72, size: 26, font: helvBold, color: CHAMPAGNE });
  }
  page.drawText(titre + "  " + (f.numero || ""), { x: 48, y: height - 104, size: 16, font: helvBold, color: BLANC });
  page.drawText("Émise le " + fmtDate(f.date_emission), { x: width - 260, y: height - 104, size: 10, font: helv, color: BLANC });

  const v = f.vendeur || {};
  const c = f.client || {};
  let y = height - 160;

  // vendeur (gauche)
  page.drawText("Émetteur", { x: 48, y, size: 9, font: helvBold, color: GRIS });
  y -= 16;
  page.drawText(v.nom || "", { x: 48, y, size: 11, font: helvBold, color: AUBERGINE });
  y -= 15;
  page.drawText("Entrepreneur individuel", { x: 48, y, size: 10, font: helv, color: AUBERGINE });
  y -= 14;
  for (const ligne of decouper(v.adresse || "", 40)) {
    page.drawText(ligne, { x: 48, y, size: 10, font: helv, color: AUBERGINE });
    y -= 14;
  }
  if ((v.siret || "").trim()) {
    page.drawText("SIRET : " + v.siret, { x: 48, y, size: 10, font: helv, color: AUBERGINE });
    y -= 14;
  }

  // client (droite)
  let cy = height - 160;
  page.drawText("Client", { x: width - 260, y: cy, size: 9, font: helvBold, color: GRIS });
  cy -= 16;
  page.drawText(c.nom || "", { x: width - 260, y: cy, size: 11, font: helvBold, color: AUBERGINE });
  cy -= 15;
  for (const ligne of decouper(c.adresse || "", 40)) {
    page.drawText(ligne, { x: width - 260, y: cy, size: 10, font: helv, color: AUBERGINE });
    cy -= 14;
  }
  if ((c.siret || "").trim()) {
    page.drawText("SIRET : " + c.siret, { x: width - 260, y: cy, size: 10, font: helv, color: AUBERGINE });
    cy -= 14;
  }

  // table (sans mention HT)
  const topTable = Math.min(y, cy) - 40;
  y = topTable;
  page.drawRectangle({ x: 48, y: y - 20, width: width - 96, height: 24, color: CHAMPAGNE });
  page.drawText("Désignation", { x: 56, y: y - 13, size: 9, font: helvBold, color: AUBERGINE });
  page.drawText("Qté", { x: 380, y: y - 13, size: 9, font: helvBold, color: AUBERGINE });
  page.drawText("Prix unitaire", { x: 415, y: y - 13, size: 9, font: helvBold, color: AUBERGINE });
  page.drawText("Total", { x: 492, y: y - 13, size: 9, font: helvBold, color: AUBERGINE });
  y -= 34;

  for (const l of (f.lignes || [])) {
    const desc = decouper(l.designation || "", 44);
    page.drawText(desc[0] || "", { x: 56, y, size: 9, font: helv, color: AUBERGINE });
    let dy = y;
    for (let i = 1; i < desc.length; i++) { dy -= 11; page.drawText(desc[i], { x: 56, y: dy, size: 9, font: helv, color: AUBERGINE }); }
    page.drawText(String(l.quantite ?? 1), { x: 380, y, size: 9, font: helv, color: AUBERGINE });
    page.drawText(fmtMontant(l.prix_unitaire || 0), { x: 415, y, size: 9, font: helv, color: AUBERGINE });
    page.drawText(fmtMontant(l.total || 0), { x: 492, y, size: 9, font: helv, color: AUBERGINE });
    y -= (desc.length > 1 ? 14 + 11 * (desc.length - 1) : 18);
  }

  // total
  y -= 12;
  page.drawText(estAvoir ? "Montant de l'avoir : " + fmtMontant(Math.abs(Number(f.total || 0))) : "Total à payer : " + fmtMontant(Number(f.total || 0)),
    { x: width - 260, y, size: 12, font: helvBold, color: AUBERGINE });
  y -= 16;
  page.drawText(v.mention_tva || "", { x: 48, y, size: 9, font: helv, color: GRIS });
  y -= 26;

  // paiement / acquittée
  const modes: Record<string, string> = { especes: "espèces", virement: "virement bancaire", carte: "carte bancaire", prelevement: "prélèvement SEPA" };
  if (f.acquittee_le) {
    page.drawText("Facture acquittée le " + fmtDate(f.acquittee_le) + " par " + (modes[f.mode_paiement] || f.mode_paiement || ""),
      { x: 48, y, size: 9, font: helv, color: AUBERGINE });
    y -= 14;
  }
  if (estAvoir && factureOrigineNumero) {
    page.drawText("Avoir sur la facture n° " + factureOrigineNumero, { x: 48, y, size: 9, font: helvBold, color: AUBERGINE });
    y -= 14;
  }
  y -= 6;
  const penalites = "Pénalités de retard : trois fois le taux d'intérêt légal. Indemnité forfaitaire pour frais de recouvrement : 40 €. Pas d'escompte pour paiement anticipé.";
  for (const ligne of decouper(penalites, 110)) {
    page.drawText(ligne, { x: 48, y, size: 8, font: helv, color: GRIS });
    y -= 10;
  }

  // pied de page centré
  const pied: string[] = [];
  if (contactEmail) pied.push("DamUp, " + contactEmail);
  const iban = (v.iban || "").trim();
  const bic = (v.bic || "").trim();
  if (iban) pied.push("IBAN : " + iban + (bic ? "  ·  BIC : " + bic : ""));
  if (pied.length) {
    let py = 56;
    for (const ligne of pied) {
      const lw = helv.widthOfTextAtSize(ligne, 9);
      page.drawText(ligne, { x: (width - lw) / 2, y: py, size: 9, font: helv, color: GRIS });
      py -= 12;
    }
  }

  return await doc.save();
}

async function envoyerBrevo(f: any, pdf: Uint8Array, admin: any) {
  const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
  const SENDER_EMAIL = Deno.env.get("SENDER_EMAIL") ?? "";
  const c = f.client || {};
  const dest = c.email || "";
  if (!dest) throw new Error("Adresse e-mail du client introuvable");

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

    // numéro de la facture d'origine (pour un avoir)
    let factureOrigineNumero: string | null = null;
    if (f.type === "avoir" && f.facture_origine) {
      const { data: fo } = await admin.from("factures").select("numero").eq("id", f.facture_origine).single();
      factureOrigineNumero = fo?.numero || null;
    }

    // e-mail de contact pour le pied de page
    let contactEmail = "";
    try {
      const { data: s } = await admin.from("settings").select("value").eq("key", "contact_email").single();
      contactEmail = (s && s.value || "").trim();
    } catch (e) { /* ignore */ }

    const pdf = await genererPdf(f, factureOrigineNumero, contactEmail);

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
