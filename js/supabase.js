// ============================================================
//  DamUp — client Supabase partagé
//  On crée UNE seule instance `sb`, réutilisée partout
//  (ne pas re-déclarer dans les autres pages).
// ============================================================
const sb = supabase.createClient(SB_URL, SB_KEY);

// Raccourcis fréquents
const auth = sb.auth;
const db = sb;

// --- Formatage partagé (affichage lisible) ---
function formatHeure(t) { if (!t) return ""; const [h, m] = t.split(":"); return `${+h}h${m}`; }
function formatDate(d) { return d ? new Date(d + "T12:00:00").toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" }) : ""; }
const LIBELLES_ARTICLES = { boisson: "Boisson", entree: "Entrée", plat: "Plat", dessert: "Dessert", chicha: "Chicha" };

// Échappement HTML : empêche le code piégé dans les textes saisis (XSS)
function esc(v) {
  return String(v ?? "").replace(/[&<>"']/g, c =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
// URL de photo sécurisée : uniquement les URLs du bucket photos, échappées
function urlPhoto(p) {
  const ok = typeof p === "string" && p.startsWith(SB_URL + "/storage/v1/object/public/photos/");
  return ok ? esc(p) : "";
}

// --- Fenêtre de signalement (partagée) ---
function ouvrirSignalement(cibleType, cibleId) {
  const motifs = ["Comportement inapproprié", "Conditions de mission non respectées", "Annonce ou profil trompeur", "Problème de sécurité", "Autre"];
  const modal = document.createElement("div");
  modal.id = "modal-signalement";
  modal.style.cssText = "position:fixed;inset:0;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;z-index:999;padding:20px";
  modal.innerHTML = `
    <div style="background:#fff;border-radius:16px;padding:20px;width:100%;max-width:360px">
      <h3 style="margin-bottom:12px">🚩 Signaler</h3>
      <div style="display:flex;flex-direction:column;gap:8px;margin-bottom:12px">
        ${motifs.map(m => `<label style="font-size:14px"><input type="radio" name="sig-motif" value="${m}"> ${m}</label>`).join("")}
      </div>
      <textarea id="sig-texte" placeholder="Décris le problème…" style="width:100%;border:1px solid #EEE4D2;border-radius:8px;padding:8px;font-size:13px;min-height:70px"></textarea>
      <div style="display:flex;gap:8px;margin-top:12px">
        <button class="btn btn-block" style="background:#EEE" onclick="document.getElementById('modal-signalement').remove()">Annuler</button>
        <button class="btn btn-block btn-primaire" onclick="envoyerSignalement('${cibleType}', '${cibleId}')">Envoyer</button>
      </div>
    </div>`;
  document.body.appendChild(modal);
}

async function envoyerSignalement(cibleType, cibleId) {
  const motif = (document.querySelector('input[name="sig-motif"]:checked') || {}).value;
  const texte = document.getElementById("sig-texte").value.trim();
  if (!motif) { toast("Choisis un motif."); return; }
  const payload = { cible_type: cibleType, cible_id: cibleId, motif: (texte ? motif + " — " + texte : motif) };
  const { error } = await db.from("signalements").insert(payload);
  document.getElementById("modal-signalement").remove();
  if (error) { toast(error.message, "erreur"); return; }
  toast("Merci, l'équipe DamUp va examiner ton signalement.");
}
