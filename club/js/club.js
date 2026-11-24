// ============================================================
//  DamUp · Espace client privé (club.damup.fr)
//  Accès par code personnel, sans compte. Lecture seule + réservation.
// ============================================================
const sb = supabase.createClient(SB_URL, SB_KEY);

const CLE_CODE = "damup_club_code";

// --- helpers ---
function esc(v) {
  return String(v ?? "").replace(/[&<>"']/g, c =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
function urlPhoto(p) {
  const ok = typeof p === "string" && p.startsWith(SB_URL + "/storage/v1/object/public/photos/");
  return ok ? esc(p) : "";
}
function formatDate(d) {
  if (!d) return "";
  const date = new Date(d + "T12:00:00");
  return date.toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long" });
}
function formatMontant(n) {
  if (n === null || n === undefined || n === "") return "";
  return Number(n).toFixed(2).replace(".", ",") + " €";
}
function $ (id) { return document.getElementById(id); }
function show(id) { document.querySelectorAll("section").forEach(s => s.hidden = true); $(id).hidden = false; }

let donnees = null;
let codeCourant = "";

// --- code ---
async function validerCode() {
  const code = $("code-input").value.trim().toUpperCase();
  $("code-erreur").hidden = true;
  if (!code) { afficherErreurCode("Entrez votre code."); return; }
  const { data, error } = await sb.rpc("espace_client_valider_code", { p_code: code });
  if (error) { afficherErreurCode("Erreur. Vérifiez le code."); return; }
  if (!data || data.valide !== true) {
    const raisons = { introuvable: "Code introuvable.", utilise: "Ce code a déjà été utilisé.", expire: "Ce code n'est plus valable." };
    afficherErreurCode(raisons[data?.raison] || "Code invalide.");
    return;
  }
  codeCourant = code;
  localStorage.setItem(CLE_CODE, code);
  await chargerDonnees();
}
function afficherErreurCode(msg) {
  const e = $("code-erreur"); e.textContent = msg; e.hidden = false;
}

// --- données ---
async function chargerDonnees() {
  const { data, error } = await sb.rpc("espace_client_donnees", { p_code: codeCourant });
  if (error || !data || data.valide !== true) { show("ecran-code"); afficherErreurCode("Code invalide."); return; }
  donnees = data;
  const bandeau = $("bandeau-soiree");
  bandeau.innerHTML = `<strong>Soirée du ${formatDate(data.date_soiree)}</strong> · ${esc(data.etablissements?.length || 0)} établissement(s)`;
  rendreEtablissements();
  $("btn-resa").hidden = false;
  show("ecran-accueil");
  window.scrollTo(0, 0);
}

function rendreEtablissements() {
  const zone = $("liste-etablissements");
  const etabs = donnees.etablissements || [];
  if (!etabs.length) {
    zone.innerHTML = `<p class="vide">Aucun établissement partenaire pour le moment.</p>`;
    return;
  }
  const restaurants = etabs.filter(e => e.type !== "club");
  const clubs = etabs.filter(e => e.type === "club");
  zone.innerHTML = blocEtablissements("Restaurants", restaurants) + blocEtablissements("Clubs", clubs);
}

function blocEtablissements(titre, etabs) {
  if (!etabs.length) return "";
  return `<h3 class="type-titre">${titre}</h3>` + etabs.map(carteEtablissement).join("");
}

function carteEtablissement(e) {
  const photo = urlPhoto(e.photos?.[0]);
  const remb = e.remboursement_pct && e.seuil_depense
    ? `<div class="remb">💸 ${esc(e.remboursement_pct)} % remboursés dès ${formatMontant(e.seuil_depense)} de dépense</div>` : "";
  const bouteilles = (e.bouteilles || []).length
    ? `<div class="bouteilles"><span class="bouteilles-titre">Carte des bouteilles</span>` +
      e.bouteilles.map(b => `<span class="bouteille">${esc(b.nom)} · ${formatMontant(b.prix)}</span>`).join("") + `</div>` : "";
  const hotesses = (e.hotesses || []).length
    ? `<div class="hotesses"><span class="hotesses-titre">Hôtesses</span><div class="hotesses-photos">` +
      e.hotesses.map(h => `<div class="hotesse"><img src="${urlPhoto(h.photo)}" alt="${esc(h.prenom)}"><span>${esc(h.prenom)}</span></div>`).join("") +
      `</div></div>` : "";
  return `<div class="carte-etab">
    ${photo ? `<img class="etab-photo" src="${photo}" alt="${esc(e.nom)}">` : ""}
    <div class="etab-corps">
      <div class="etab-nom">${esc(e.nom)}</div>
      <div class="etab-ville">${esc(e.type || "")} · ${esc(e.ville || "")}</div>
      ${remb}${bouteilles}${hotesses}
    </div>
  </div>`;
}

// --- réservation ---
function ouvrirReservation() {
  const etabs = donnees.etablissements || [];
  const restaurants = etabs.filter(e => e.type !== "club");
  const clubs = etabs.filter(e => e.type === "club");
  remplirSelect("resa-restaurant", restaurants, "Choisir un restaurant (optionnel)");
  remplirSelect("resa-club", clubs, "Choisir un club (optionnel)");
  $("resa-nom").value = donnees.client_nom || "";
  $("resa-erreur").hidden = true;
  majBouteilles();
  show("ecran-reservation");
  window.scrollTo(0, 0);
}
function remplirSelect(id, etabs, placeholder) {
  const sel = $(id);
  sel.innerHTML = `<option value="">${placeholder}</option>` + etabs.map(e => `<option value="${e.id}">${esc(e.nom)}</option>`).join("");
}
function majBouteilles() {
  const clubId = $("resa-club").value;
  const bloc = $("bloc-bouteille");
  const sel = $("resa-bouteille");
  if (!clubId) { bloc.hidden = true; sel.innerHTML = ""; return; }
  const club = (donnees.etablissements || []).find(e => e.id === clubId);
  const bouteilles = club?.bouteilles || [];
  sel.innerHTML = `<option value="">Choisir une bouteille</option>` + bouteilles.map(b => `<option value="${b.id}">${esc(b.nom)} · ${formatMontant(b.prix)}</option>`).join("");
  bloc.hidden = false;
}
async function envoyerReservation() {
  $("resa-erreur").hidden = true;
  const nom = $("resa-nom").value.trim();
  const restaurant = $("resa-restaurant").value || null;
  const club = $("resa-club").value || null;
  const bouteille = $("resa-bouteille").value || null;
  if (!restaurant && !club) { afficherErreurResa("Choisissez au moins un établissement."); return; }
  if (club && !bouteille) { afficherErreurResa("Choisissez une bouteille pour le club."); return; }
  const { data, error } = await sb.rpc("espace_client_reserver", {
    p_code: codeCourant, p_client_nom: nom, p_restaurant_id: restaurant, p_club_id: club, p_bouteille_id: bouteille,
  });
  if (error || !data?.ok) { afficherErreurResa(data?.erreur || error?.message || "Erreur lors de la réservation."); return; }
  afficherReservations();
}
function afficherErreurResa(msg) {
  const e = $("resa-erreur"); e.textContent = msg; e.hidden = false;
}

// --- mes réservations ---
async function afficherReservations() {
  const { data, error } = await sb.rpc("espace_client_mes_reservations", { p_code: codeCourant });
  const zone = $("liste-reservations");
  const resas = data?.reservations || [];
  if (!resas.length) zone.innerHTML = `<p class="vide">Aucune réservation pour le moment.</p>`;
  else zone.innerHTML = resas.map(carteReservation).join("");
  show("ecran-reservations");
  window.scrollTo(0, 0);
}
function carteReservation(r) {
  const badges = { nouvelle: "Nouvelle", transmise: "Transmise à l'établissement", confirmee: "Confirmée", terminee: "Terminée", annulee: "Annulée" };
  const lieux = [r.restaurant, r.club].filter(Boolean).join(" + ");
  const remb = r.remboursement > 0
    ? `<div class="remb-resa">💸 Remboursement DamUp : ${formatMontant(r.remboursement)}</div>` : "";
  return `<div class="carte-resa">
    <div class="resa-statut statut-${esc(r.statut)}">${badges[r.statut] || esc(r.statut)}</div>
    <div class="resa-date">${formatDate(r.date_soiree)}</div>
    <div class="resa-lieux">${esc(lieux)}${r.bouteille ? ` · Bouteille : ${esc(r.bouteille)}` : ""}</div>
    ${r.depense ? `<div class="resa-depense">Dépense : ${formatMontant(r.depense)}</div>` : ""}
    ${remb}
  </div>`;
}

function retourAccueil() { if (donnees) { show("ecran-accueil"); window.scrollTo(0, 0); } }

// --- démarrage : si un code est déjà enregistré, on reprend ---
(function init() {
  const code = localStorage.getItem(CLE_CODE);
  if (code) {
    $("code-input").value = code;
    codeCourant = code;
    chargerDonnees();
  } else {
    show("ecran-code");
  }
})();
