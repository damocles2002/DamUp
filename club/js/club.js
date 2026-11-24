// ============================================================
//  DamUp · Espace client privé (club.damup.fr)
//  Code personnel → établissements + hôtesses → réservation
//  → remboursement. Sans compte, tout passe par le code.
// ============================================================
const sb = supabase.createClient(SB_URL, SB_KEY);
const CLE_CODE = "damup_club_code";

// --- helpers ---
function esc(v) { return String(v ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function urlPhoto(p) { const ok = typeof p === "string" && p.startsWith(SB_URL + "/storage/v1/object/public/photos/"); return ok ? esc(p) : ""; }
function fmtDate(d) { if (!d) return ""; const x = new Date(d + "T12:00:00"); return x.toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long" }); }
function fmtDateCourte(d) { if (!d) return ""; const x = new Date(d + "T12:00:00"); return x.toLocaleDateString("fr-FR", { day: "numeric", month: "short" }); }
function fmtMontant(n) { if (n === null || n === undefined || n === "") return ""; return Number(n).toFixed(2).replace(".", ",") + " €"; }
function $(id) { return document.getElementById(id); }
function montrer(id) { document.querySelectorAll("main > section").forEach(s => s.hidden = true); $(id).hidden = false; $("topbar").hidden = false; window.scrollTo(0, 0); }

let donnees = null;
let code = "";
let client = null;
let ficheCourante = null;

// --- entrée / code ---
async function validerCode() {
  $("code-erreur").hidden = true;
  const saisie = $("code-input").value.trim();
  if (!saisie) { err("Entrez votre code."); return; }
  const { data, error } = await sb.rpc("espace_client_valider_code", { p_code: saisie });
  if (error || !data || data.valide !== true) { err("Code invalide ou expiré. Contactez DamUp."); return; }
  code = saisie;
  client = data;
  localStorage.setItem(CLE_CODE, code);
  if (!data.majeur_confirme) {
    $("bloc-majeur").hidden = false;
    if (!$("ck-majeur").checked) { err("Confirmez que vous avez 18 ans ou plus."); return; }
    await sb.rpc("espace_client_confirmer_majeur", { p_code: code });
  }
  await chargerDonnees();
}
function err(m) { const e = $("code-erreur"); e.textContent = m; e.hidden = false; }

// --- données ---
async function chargerDonnees() {
  const { data, error } = await sb.rpc("espace_client_donnees", { p_code: code });
  if (error || !data || data.valide !== true) { montrer("ecran-entree"); err("Code invalide ou expiré. Contactez DamUp."); return; }
  donnees = data;
  $("bandeau-soiree").innerHTML = `<strong>Soirée du ${fmtDate(data.date_soiree)}</strong>`;
  filtrer("tous");
  montrer("ecran-etablissements");
}

function filtrer(type) {
  ["tous", "restaurant", "club"].forEach(t => $("f-" + t).classList.toggle("on", t === type));
  const etabs = (donnees.etablissements || []).filter(e => type === "tous" ? true : (type === "club" ? e.type === "club" : e.type !== "club"));
  const zone = $("liste-etablissements");
  zone.innerHTML = etabs.length ? etabs.map(carteEtab).join("") : `<p class="vide">Aucun établissement pour le moment.</p>`;
}

function avantage(e) {
  if (!e.seuil_depense_eur || !e.pourcentage_client) return "";
  const club = e.bouteille_obligatoire ? " · 1 bouteille obligatoire" : "";
  return `<div class="avantage">Remboursé ${esc(e.pourcentage_client)} % dès ${fmtMontant(e.seuil_depense_eur)} dépensés${club}</div>`;
}

function carteEtab(e) {
  const photo = urlPhoto(e.photos?.[0]);
  return `<div class="carte-etab" onclick="ouvrirFiche('${e.id}')">
    ${photo ? `<img class="etab-photo" src="${photo}" alt="${esc(e.nom)}">` : `<div class="etab-photo-vide">${esc(e.nom[0] || "?")}</div>`}
    <div class="etab-corps">
      <div class="etab-nom">${esc(e.nom)}</div>
      <div class="etab-ville">${esc(e.type || "")} · ${esc(e.ville || "")}</div>
      ${avantage(e)}
    </div>
  </div>`;
}

// --- fiche établissement ---
function ouvrirFiche(id) {
  ficheCourante = (donnees.etablissements || []).find(e => e.id === id);
  if (!ficheCourante) return;
  const e = ficheCourante;
  const photos = (e.photos || []).map(urlPhoto).filter(Boolean);
  const hotesses = (e.hotesses || []);
  const bouteilles = (e.bouteilles || []);
  $("fiche-contenu").innerHTML = `
    <button class="btn-retour" onclick="retourEtablissements()">‹ Retour</button>
    ${photos.length ? `<div class="galerie">${photos.map(p => `<img src="${p}" onclick="agrandir('${p}')">`).join("")}</div>` : ""}
    <h1>${esc(e.nom)}</h1>
    <div class="etab-ville">${esc(e.type || "")} · ${esc(e.ville || "")}${e.adresse ? " · " + esc(e.adresse) : ""}</div>
    ${avantage(e)}
    <h3 class="bloc-titre">Les hôtesses présentes ce soir</h3>
    ${hotesses.length ? `<div class="hotesses-photos">${hotesses.map(h => `<div class="hotesse"><img src="${urlPhoto(h.photo)}" alt="${esc(h.prenom)}"><span>${esc(h.prenom)}</span></div>`).join("")}</div>`
      : `<p class="vide-mini">Les hôtesses de ce soir ne sont pas encore annoncées.</p>`}
    ${bouteilles.length ? `<h3 class="bloc-titre">Carte des bouteilles</h3><div class="bouteilles">${bouteilles.map(b => `<div class="bouteille"><span>${esc(b.nom)}${b.categorie ? " · " + esc(b.categorie) : ""}${b.contenance_cl ? " · " + b.contenance_cl + " cl" : ""}</span><strong>${fmtMontant(b.prix_eur)}</strong></div>`).join("")}</div>` : ""}
    <h3 class="bloc-titre">Simulateur</h3>
    <div class="simulateur">
      <input id="sim-montant" class="field" type="number" placeholder="Ex. 400" oninput="simuler()">
      <div id="sim-resultat" class="sim-resultat"></div>
    </div>
    <button class="btn btn-primaire btn-block" onclick="ouvrirReservation()">Réserver une table</button>`;
  montrer("ecran-fiche");
}

function agrandir(url) {
  const m = document.createElement("div");
  m.className = "modal";
  m.innerHTML = `<img src="${url}" style="max-width:94vw;max-height:90vh;border-radius:12px" onclick="this.parentElement.remove()">`;
  m.onclick = () => m.remove();
  m.style.display = "flex";
  document.body.appendChild(m);
}

async function simuler() {
  const montant = parseFloat($("sim-montant").value) || 0;
  const zone = $("sim-resultat");
  if (!montant || !ficheCourante) { zone.innerHTML = ""; return; }
  const { data } = await sb.rpc("espace_client_simuler", { p_code: code, p_etablissement_id: ficheCourante.id, p_montant: montant });
  if (!data?.valide) { zone.innerHTML = ""; return; }
  zone.innerHTML = data.rembourse > 0
    ? `Vous serez remboursé de <strong>${fmtMontant(data.rembourse)}</strong>.`
    : `Encore <strong>${fmtMontant(data.manque)}</strong> de dépense pour être remboursé.`;
}

// --- réservation ---
function ouvrirReservation() {
  const e = ficheCourante;
  $("resa-etab-nom").textContent = `${e.nom} · ${fmtDate(donnees.date_soiree)}`;
  $("resa-recap").innerHTML = avantage(e);
  // heures par tranches de 30 min (18h à 02h)
  const heures = [];
  for (let h = 18; h <= 26; h++) for (const m of [0, 30]) { const hh = h % 24; heures.push(`${String(hh).padStart(2, "0")}:${String(m).padStart(2, "0")}`); }
  $("resa-heure").innerHTML = heures.map(h => `<option value="${h}">${h}</option>`).join("");
  if (e.bouteille_obligatoire) {
    $("bloc-bouteille").hidden = false;
    $("resa-bouteille").innerHTML = `<option value="">Choisir une bouteille</option>` + (e.bouteilles || []).map(b => `<option value="${b.id}">${esc(b.nom)} · ${fmtMontant(b.prix_eur)}</option>`).join("");
  } else {
    $("bloc-bouteille").hidden = true;
  }
  $("resa-erreur").hidden = true;
  montrer("ecran-reservation");
}

async function envoyerReservation() {
  $("resa-erreur").hidden = true;
  const heure = $("resa-heure").value;
  const personnes = parseInt($("resa-personnes").value) || 1;
  const bouteille = $("resa-bouteille").value || null;
  const message = $("resa-message").value.trim();
  if (ficheCourante.bouteille_obligatoire && !bouteille) { resaErr("Choisissez une bouteille."); return; }
  const { data, error } = await sb.rpc("espace_client_reserver", {
    p_code: code, p_etablissement_id: ficheCourante.id, p_heure_arrivee: heure,
    p_nb_personnes: personnes, p_bouteille_id: bouteille, p_message: message,
  });
  if (error || !data?.ok) { resaErr(data?.erreur || "Erreur lors de la réservation."); return; }
  afficherReservations();
}
function resaErr(m) { const e = $("resa-erreur"); e.textContent = m; e.hidden = false; }

// --- mes réservations ---
const STATUTS = { en_attente: "En attente", transmise: "Transmise", confirmee: "Confirmée", refusee: "Refusée", terminee: "Terminée", no_show: "No-show", annulee: "Annulée" };

async function afficherReservations() {
  const { data } = await sb.rpc("espace_client_mes_reservations", { p_code: code });
  const resas = data?.reservations || [];
  const zone = $("liste-reservations");
  zone.innerHTML = resas.length ? resas.map(carteResa).join("") : `<p class="vide">Aucune réservation pour le moment.</p>`;
  montrer("ecran-reservations");
}

function carteResa(r) {
  const annulable = !["terminee", "no_show", "refusee", "annulee"].includes(r.statut);
  const remboursable = r.statut === "terminee";
  return `<div class="carte-resa">
    <div class="resa-statut statut-${esc(r.statut)}">${STATUTS[r.statut] || esc(r.statut)}</div>
    <div class="resa-date">${fmtDateCourte(r.date_soiree)} · ${esc(r.heure_arrivee || "")} · ${r.nb_personnes} pers.</div>
    <div class="resa-lieux">${esc(r.etablissement)}${r.bouteille ? ` · ${esc(r.bouteille)}` : ""}</div>
    ${r.motif_refus ? `<div class="resa-refus">Refus : ${esc(r.motif_refus)}</div>` : ""}
    ${r.remboursement != null && r.remboursement > 0 ? `<div class="remb-resa">Remboursement : ${fmtMontant(r.remboursement)}</div>` : ""}
    <div class="resa-actions">
      ${annulable ? `<button class="btn btn-sm btn-danger" onclick="annulerResa('${r.id}')">Annuler</button>` : ""}
      ${remboursable ? `<button class="btn btn-sm btn-primaire" onclick="ouvrirRemboursement('${r.id}')">Remboursement</button>` : ""}
    </div>
  </div>`;
}

async function annulerResa(id) {
  if (!confirm("Annuler cette réservation ?")) return;
  const { data } = await sb.rpc("espace_client_annuler", { p_code: code, p_reservation: id });
  if (data?.ok) afficherReservations();
}

// --- remboursement ---
function ouvrirRemboursement(id) {
  $("remboursement-contenu").innerHTML = `
    <p class="sous-titre">Envoyez vos informations pour être remboursé.</p>
    <label class="label">Moyen de paiement</label>
    <select id="rb-moyen" class="field">
      <option value="virement">Virement (IBAN)</option>
      <option value="wero">Wero (téléphone)</option>
      <option value="lydia">Lydia (téléphone)</option>
    </select>
    <label class="label" id="rb-coord-label">IBAN</label>
    <input id="rb-coord" class="field" placeholder="FR76 …">
    <button class="btn btn-primaire btn-block" onclick="envoyerRemboursement('${id}')">Envoyer</button>
    <p class="note">DamUp vérifie le montant auprès de l'établissement avant de payer. Le remboursement arrive sous quelques jours.</p>`;
  $("rb-moyen").onchange = () => {
    $("rb-coord-label").textContent = $("rb-moyen").value === "virement" ? "IBAN" : "Numéro de téléphone";
    $("rb-coord").placeholder = $("rb-moyen").value === "virement" ? "FR76 …" : "06 …";
  };
  montrer("ecran-remboursement");
}

async function envoyerRemboursement(id) {
  const moyen = $("rb-moyen").value;
  const coord = $("rb-coord").value.trim();
  if (!coord) { alert("Indiquez vos coordonnées."); return; }
  const { data, error } = await sb.rpc("espace_client_envoyer_facture", { p_code: code, p_reservation_id: id, p_photo_facture: null, p_moyen_paiement: moyen, p_coordonnees: coord });
  if (error || !data?.ok) { alert("Erreur. Réessayez."); return; }
  alert("Bien reçu ! DamUp validera votre remboursement prochainement.");
  afficherReservations();
}

// --- navigation ---
function retourEtablissements() { montrer("ecran-etablissements"); }
function retourFiche() { if (ficheCourante) ouvrirFiche(ficheCourante.id); }
function ouvrirConditions() { $("modal-conditions").hidden = false; $("modal-conditions").style.display = "flex"; }
function fermerConditions() { $("modal-conditions").hidden = true; $("modal-conditions").style.display = "none"; }

// --- démarrage ---
(function init() {
  const c = localStorage.getItem(CLE_CODE);
  if (c) {
    code = c;
    $("code-input").value = c;
    sb.rpc("espace_client_valider_code", { p_code: c }).then(({ data }) => {
      if (data?.valide) { client = data; chargerDonnees(); }
      else { montrer("ecran-entree"); $("topbar").hidden = true; }
    });
  } else {
    montrer("ecran-entree");
    $("topbar").hidden = true;
  }
})();
