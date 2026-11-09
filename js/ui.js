// ============================================================
//  DamUp — UI partagée : toast + fenêtre de confirmation
//  Remplace toast() et await demander() du navigateur.
// ============================================================

// Message d'erreur lisible (traduit si possible) — à utiliser partout où une erreur remonte
function messageErreur(error) {
  const msg = (error?.message || error?.error_description || error?.hint || "").toString().trim();
  if (!msg) return (typeof t === "function" ? t("login.msg_erreur") : "Une erreur est survenue.");
  const map = [
    ["Invalid login credentials", "login.msg_email_incorrect"],
    ["User already registered", "login.msg_deja_compte"],
    ["Email not confirmed", "login.msg_confirme"],
    ["Password should be", "mdp.regles_requises"],
    ["breach", "mdp.compromis"],
    ["weak", "mdp.regles_requises"],
    ["JWT", "err.session"],
  ];
  for (const [frag, cle] of map) {
    if (msg.includes(frag)) { if (typeof t === "function") return t(cle); return msg; }
  }
  return msg;
}

// Bandeau de notification en bas de l'écran (4 s)
function toast(message, type = "info") {
  const couleurs = { ok: "#1E7A3C", erreur: "#C0392B", info: "#2A1120" };
  const fonds = { ok: "#E7F5EC", erreur: "#FBE4E1", info: "#F4E8D6" };
  const el = document.createElement("div");
  el.textContent = message;
  el.style.cssText = "position:fixed;left:50%;bottom:90px;transform:translateX(-50%);max-width:90%;" +
    "background:" + (fonds[type] || fonds.info) + ";color:" + (couleurs[type] || couleurs.info) + ";" +
    "padding:12px 18px;border-radius:12px;font-size:14px;font-weight:500;" +
    "box-shadow:0 6px 24px rgba(0,0,0,.18);z-index:9999;text-align:center;" +
    "opacity:0;transition:opacity .25s;";
  document.body.appendChild(el);
  requestAnimationFrame(() => { el.style.opacity = "1"; });
  setTimeout(() => { el.style.opacity = "0"; setTimeout(() => el.remove(), 300); }, 4000);
}

// Petite fenêtre de confirmation (promesse true / false)
function demander(question, libelleOui = "Oui") {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.style.cssText = "position:fixed;inset:0;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;z-index:9998;padding:20px";
    const box = document.createElement("div");
    box.style.cssText = "background:#fff;border-radius:16px;padding:22px;width:100%;max-width:340px;text-align:center";
    const q = document.createElement("div");
    q.textContent = question;
    q.style.cssText = "font-size:15px;margin-bottom:18px;white-space:pre-line";
    const actions = document.createElement("div");
    actions.style.cssText = "display:flex;gap:10px";
    const non = document.createElement("button");
    non.textContent = "Annuler";
    non.style.cssText = "flex:1;padding:12px;border:none;border-radius:10px;background:#EEE;font-size:14px;font-weight:600;cursor:pointer";
    const oui = document.createElement("button");
    oui.textContent = libelleOui;
    oui.style.cssText = "flex:1;padding:12px;border:none;border-radius:10px;background:#2A1120;color:#fff;font-size:14px;font-weight:600;cursor:pointer";
    actions.appendChild(non);
    actions.appendChild(oui);
    box.appendChild(q);
    box.appendChild(actions);
    overlay.appendChild(box);
    document.body.appendChild(overlay);
    const fin = (val) => { overlay.remove(); resolve(val); };
    oui.onclick = () => fin(true);
    non.onclick = () => fin(false);
    overlay.addEventListener("click", (e) => { if (e.target === overlay) fin(false); });
  });
}

// Redimensionne une image côté navigateur (canvas), JPEG qualité 0.8, max 1600 px
function redimensionnerImage(file, maxCote = 1600, qualite = 0.8) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      URL.revokeObjectURL(url);
      let { width, height } = img;
      const ratio = Math.min(1, maxCote / Math.max(width, height));
      if (ratio < 1) { width = Math.round(width * ratio); height = Math.round(height * ratio); }
      const canvas = document.createElement("canvas");
      canvas.width = width; canvas.height = height;
      canvas.getContext("2d").drawImage(img, 0, 0, width, height);
      canvas.toBlob((blob) => { blob ? resolve(blob) : reject(new Error("Impossible de traiter l'image")); }, "image/jpeg", qualite);
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("Image invalide")); };
    img.src = url;
  });
}

// Bloc "Mon abonnement" (appelé depuis profil établissement / hôtesse)
async function afficherBlocAbonnement(conteneurId) {
  const conteneur = document.getElementById(conteneurId);
  if (!conteneur) return;
  const { data: { user } } = await auth.getUser();
  if (!user) return;
  const { data: profil } = await db.from("profiles").select("type, tarif, periode, actif_jusqu_a, stripe_customer_id").eq("id", user.id).single();
  const { data: paiements } = await db.from("paiements").select("*").eq("profil_id", user.id).order("created_at", { ascending: false });
  const type = profil?.type;
  const cleType = type === "etablissement" ? "paiement_etablissements_actif" : "paiement_hotesses_actif";
  const [rEnLigne, rType] = await Promise.all([
    db.from("settings").select("value").eq("key", "paiement_en_ligne_actif").single(),
    db.from("settings").select("value").eq("key", cleType).single(),
  ]);
  const enLigneActif = rEnLigne.data?.value === "true";
  const doitPayer = rType.data?.value === "true";
  const actif = profil?.actif_jusqu_a ? new Date(profil.actif_jusqu_a) : null;
  const actifOk = actif && actif > new Date();
  const periode = profil?.periode === "hebdomadaire" ? "semaine" : "mois";
  const dejaClient = !!profil?.stripe_customer_id;
  // coordonnées bancaires pour le virement (établissement seulement)
  let virement = null;
  if (type === "etablissement") {
    const [rIban, rBic, rTit] = await Promise.all([
      db.from("settings").select("value").eq("key", "iban").single(),
      db.from("settings").select("value").eq("key", "bic").single(),
      db.from("settings").select("value").eq("key", "titulaire_iban").single(),
    ]);
    const iban = (rIban.data?.value || "").trim();
    if (iban) {
      const { data: ref } = await db.rpc("reference_virement", { p_uid: user.id });
      virement = { iban, bic: (rBic.data?.value || "").trim(), titulaire: (rTit.data?.value || "").trim(), reference: ref || "" };
    }
  }
  conteneur.innerHTML = `
    <div class="panneau" style="margin:14px 18px">
      <div class="tete">Mon abonnement</div>
      <div style="padding:16px">
        <div style="font-size:14px;margin-bottom:8px">Statut : ${actif ? (actifOk ? 'Actif jusqu\u2019au <b>' + actif.toLocaleDateString("fr-FR") + '</b>' : 'Expiré le ' + actif.toLocaleDateString("fr-FR")) : 'Essai gratuit'}</div>
        <div style="font-size:13px;color:var(--gris);margin-bottom:12px">Tarif : ${profil?.tarif ? profil.tarif + ' € / ' + periode : 'non défini'}</div>
        ${doitPayer ? (enLigneActif
          ? `<button class="btn btn-primaire btn-sm" onclick="lancerPaiement(${dejaClient})">${dejaClient ? "Gérer mon abonnement" : "S'abonner"}</button>`
          : '<span style="font-size:12.5px;color:var(--gris)">Le paiement en ligne n\u2019est pas encore actif. Contacte DamUp pour régler en espèces.</span>')
          : '<span style="font-size:12.5px;color:var(--gris)">Aucun paiement requis pour le moment.</span>'}
        ${(paiements && paiements.length) ? `<div style="margin-top:12px;border-top:1px solid #EEE;padding-top:10px">
          <div style="font-size:12.5px;color:var(--gris);margin-bottom:6px">Mes reçus :</div>
          ${paiements.slice(0, 5).map(p => `<div style="display:flex;justify-content:space-between;font-size:12.5px;padding:4px 0"><span>${esc(p.numero_recu)} · ${Number(p.montant).toFixed(2)} €</span><a href="recu.html?id=${p.id}" target="_blank" style="color:var(--aubergine)">Reçu</a></div>`).join("")}
        </div>` : ""}
        ${virement ? `<div style="margin-top:12px;border-top:1px solid #EEE;padding-top:10px">
          <div style="font-weight:600;font-size:13.5px;margin-bottom:8px">🏦 Payer par virement</div>
          <div style="font-size:12.5px;line-height:1.9">
            ${virement.titulaire ? `Titulaire : <b>${esc(virement.titulaire)}</b><br>` : ""}
            IBAN : <b>${esc(virement.iban)}</b> <a style="color:var(--aubergine);cursor:pointer;font-size:11.5px" onclick="navigator.clipboard.writeText('${esc(virement.iban)}')">Copier</a><br>
            ${virement.bic ? `BIC : <b>${esc(virement.bic)}</b> <a style="color:var(--aubergine);cursor:pointer;font-size:11.5px" onclick="navigator.clipboard.writeText('${esc(virement.bic)}')">Copier</a><br>` : ""}
            Montant : <b>${profil?.tarif ? Number(profil.tarif).toFixed(2).replace(".", ",") + " €" : "—"}</b><br>
            Référence à indiquer : <b>${esc(virement.reference)}</b> <a style="color:var(--aubergine);cursor:pointer;font-size:11.5px" onclick="navigator.clipboard.writeText('${esc(virement.reference)}')">Copier</a>
          </div>
          <div style="font-size:11.5px;color:var(--gris);margin-top:6px">Ton abonnement est prolongé dès réception du virement (1 à 2 jours ouvrés).</div>
        </div>` : ""}
      </div>
    </div>`;
}

async function lancerPaiement(gerer = false) {
  const fn = gerer ? "paiement-portail" : "paiement-creer";
  const { data, error } = await db.functions.invoke(fn, { body: {} });
  if (error) { toast(error.message || "Erreur", "erreur"); return; }
  if (data?.url) location.href = data.url;
  else if (data?.error) toast(data.error, "erreur");
}

// Vérification de la maintenance (auto au chargement, sauf admin/login/reinitialiser)
document.addEventListener("DOMContentLoaded", async () => {
  if (/admin|login|reinitialiser/.test(location.pathname)) return;
  try {
    const { data: m } = await db.from("settings").select("value").eq("key", "maintenance").single();
    if (!m || (m.value !== "true" && m.value !== true)) return;
    const { data: u } = await auth.getUser();
    if (u && u.user) {
      const { data: p } = await db.from("profiles").select("type").eq("id", u.user.id).single();
      if (p && p.type === "admin") return;
    }
    const { data: mm } = await db.from("settings").select("value").eq("key", "maintenance_message").single();
    document.body.innerHTML = `<div style="display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px;text-align:center;background:#F4E8D6"><div><div style="font-size:40px;margin-bottom:10px">🛠️</div><p style="font-size:16px;max-width:320px">${esc(mm?.value || "DamUp est en maintenance, reviens dans quelques minutes.")}</p></div></div>`;
  } catch (e) {}
});
