// ============================================================
//  DamUp — proposer une copine (écrans 👯)
//  Fonctions partagées entre hotesse.html et hotesse-profil.html
// ============================================================

function statutCopine(statut) {
  const map = {
    envoyee: "copine.statut_envoyee",
    a_accepter: "copine.statut_a_accepter",
    acceptee: "copine.statut_acceptee",
    refusee: "copine.statut_refusee",
    expiree: "copine.statut_expiree",
  };
  return map[statut] || statut;
}

function formaterDateCopine(d) {
  if (!d) return "";
  const j = new Date(d + "T00:00:00");
  if (isNaN(j.getTime())) return d;
  return j.toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" });
}

// --- Écran 1 : fenêtre « Tu viens avec une copine ? » ---
async function ouvrirProposerCopine(candidatureId) {
  const { data: c } = await db.from("candidatures")
    .select("id, mission_id, missions(date, heure_debut, places_restantes, nb_hotesses, etablissements(nom))")
    .eq("id", candidatureId).single();
  if (!c || !c.missions) { toast("Candidature introuvable."); return; }
  const m = c.missions;
  const places = m.places_restantes ?? m.nb_hotesses;
  window._copine_lieu = m.etablissements?.nom || "";
  window._copine_date = formaterDateCopine(m.date);

  const ov = document.createElement("div");
  ov.id = "overlay-copine";
  ov.style.cssText = "position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:1000;display:flex;align-items:flex-end;justify-content:center";
  ov.innerHTML = `
    <div style="background:#fff;border-radius:18px 18px 0 0;width:100%;max-width:430px;max-height:90vh;overflow-y:auto;padding:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
        <h3 style="font-family:var(--font-titre);font-size:18px;margin:0">${t("copine.titre")}</h3>
        <button style="background:none;border:none;font-size:20px;cursor:pointer" onclick="document.getElementById('overlay-copine').remove()">✕</button>
      </div>
      <div style="font-size:13px;color:var(--gris);margin-bottom:8px">${t("copine.places", { n: places })}</div>
      ${places <= 1 ? `<div style="background:#FFF3E0;color:#9A5B00;border-radius:10px;padding:10px;font-size:12.5px;margin-bottom:12px">${t("copine.une_place")}</div>` : ""}
      <div style="border:1.5px solid #EADFCC;border-radius:12px;padding:12px;margin-bottom:12px">
        <div style="font-weight:700;font-size:13.5px;margin-bottom:8px">${t("copine.choix_code_titre")}</div>
        <input class="field" id="copine-code" placeholder="${t("copine.code_placeholder")}" maxlength="6" style="text-transform:uppercase">
        <button class="btn btn-primaire btn-block btn-sm" style="margin-top:8px" onclick="envoyerCopineCode('${candidatureId}')">${t("copine.envoyer")}</button>
      </div>
      <div style="border:1.5px solid #EADFCC;border-radius:12px;padding:12px">
        <div style="font-weight:700;font-size:13.5px;margin-bottom:8px">${t("copine.choix_lien_titre")}</div>
        <input class="field" id="copine-prenom" placeholder="${t("copine.prenom_placeholder")}">
        <button class="btn btn-primaire btn-block btn-sm" style="margin-top:8px" onclick="envoyerCopineLien('${candidatureId}')">${t("copine.whatsapp")}</button>
        <button class="btn btn-block btn-sm" id="btn-copier-lien" style="margin-top:6px;background:var(--ivoire);color:var(--aubergine);display:none">${t("copine.copier_lien")}</button>
      </div>
      <button class="btn btn-block" style="margin-top:12px;background:transparent;color:var(--gris)" onclick="document.getElementById('overlay-copine').remove()">${t("copine.plus_tard")}</button>
    </div>`;
  document.body.appendChild(ov);
}

async function envoyerCopineCode(candidatureId) {
  const code = (document.getElementById("copine-code")?.value || "").trim();
  if (!code) { toast(t("copine.code_manquant")); return; }
  const { error } = await db.rpc("proposer_copine", { p_candidature: candidatureId, p_code_damup: code, p_prenom: null });
  if (error) { toast(error.message); return; }
  document.getElementById("overlay-copine")?.remove();
  toast(t("copine.envoyee"));
}

async function envoyerCopineLien(candidatureId) {
  const prenom = (document.getElementById("copine-prenom")?.value || "").trim();
  if (!prenom) { toast(t("copine.prenom_manquant")); return; }
  const { data: codeInv, error } = await db.rpc("proposer_copine", { p_candidature: candidatureId, p_code_damup: null, p_prenom: prenom });
  if (error) { toast(error.message); return; }
  if (!codeInv) { document.getElementById("overlay-copine")?.remove(); toast(t("copine.envoyee")); return; }
  const lien = SITE_URL + "/login.html?mode=inscription&role=hotesse&invitation=" + codeInv;
  const texte = t("copine.texte_whatsapp", { lieu: window._copine_lieu || "", date: window._copine_date || "", lien });
  window.open("https://wa.me/?text=" + encodeURIComponent(texte), "_blank");
  const btn = document.getElementById("btn-copier-lien");
  if (btn) {
    btn.style.display = "block";
    btn.onclick = () => { (navigator.clipboard ? navigator.clipboard.writeText(lien) : Promise.reject()).then(() => toast(t("commun.copie"))); };
  }
}

// --- Écran 2 : bloc « Invitations 👯 » ---
async function chargerInvitationsCopine(containerId) {
  const zone = document.getElementById(containerId);
  if (!zone) return;
  const { data: invs } = await db.from("invitations_copine")
    .select("id, statut").eq("copine_id", user.id).eq("statut", "a_accepter");
  if (!invs || !invs.length) { zone.innerHTML = ""; return; }
  const details = [];
  for (const inv of invs) {
    const { data: d } = await db.rpc("invitation_copine_detail", { p_invitation: inv.id });
    if (d) details.push({ id: inv.id, ...d });
  }
  zone.innerHTML = details.map(d => {
    const m = d.mission, e = m?.etablissement;
    const offres = (m?.articles_offerts || []).map(a => `<span>${(typeof ICONES !== "undefined" ? ICONES[a] : "•") || "•"} ${(typeof LIBELLES_ARTICLES !== "undefined" ? LIBELLES_ARTICLES[a] : a) || a}</span>`).join("");
    return `<div class="avis">
      <div class="txt" style="font-weight:600">${t("copine.invitation_texte", { prenom: esc(d.marraine_prenom || "") })}</div>
      <div class="t"><span class="e">${esc(e?.nom || "")}</span></div>
      <div class="txt">📅 ${formaterDateCopine(m?.date)} · 🕗 ${m?.heure_debut || ""}–${m?.heure_fin || ""}</div>
      <div class="txt">📍 ${esc(m?.adresse || e?.ville || "")}</div>
      ${offres ? `<div class="offres" style="margin:6px 0">${offres}</div>` : ""}
      ${m?.note ? `<div class="txt" style="white-space:pre-line">📝 ${esc(m.note)}</div>` : ""}
      <div style="display:flex;gap:8px;margin-top:10px">
        <button class="btn btn-primaire btn-sm" style="flex:1" onclick="repondreInvitation('${d.id}', true)">${t("copine.accepter")}</button>
        <button class="btn btn-sm" style="background:#FBE4E1;color:var(--danger)" onclick="repondreInvitation('${d.id}', false)">${t("copine.refuser")}</button>
      </div>
    </div>`;
  }).join("");
}

async function repondreInvitation(id, accepte) {
  if (accepte) {
    const { data: h } = await db.from("hotesses").select("photos").eq("id", user.id).single();
    if ((h?.photos || []).length < 4) { toast(t("copine.photos_min")); return; }
  }
  const { error } = await db.rpc("repondre_invitation", { p_invitation: id, p_accepte: accepte });
  if (error) { toast(error.message); return; }
  toast(accepte ? t("copine.acceptee") : t("copine.refusee"));
  chargerInvitationsCopine("invitations-copine");
}
