// ============================================================
//  DamUp — Messagerie (une conversation par mission)
// ============================================================
let _canalMessages = null;
let _convOuverte = null; // { mission_id, hotesse_id, nom, photo, type }

function _estEtab() { return window._damup_type === "etablissement"; }

async function _mesConversations() {
  const { data: { user } } = await auth.getUser();
  if (!user) return [];
  const { data: p } = await db.from("profiles").select("type").eq("id", user.id).single();
  const estEtab = p?.type === "etablissement";
  if (estEtab) {
    const { data: cands } = await db.from("candidatures")
      .select("mission_id, hotesse_id, missions(date, heure_debut, heure_fin), hotesses(prenom, photos)")
      .in("statut", ["acceptee", "confirmee"])
      .eq("annulation", false);
    const { data: mesMissions } = await db.from("missions").select("id").eq("etablissement_id", user.id);
    const ids = new Set((mesMissions || []).map(m => m.id));
    return (cands || []).filter(c => ids.has(c.mission_id)).map(c => ({
      mission_id: c.mission_id, hotesse_id: c.hotesse_id,
      nom: c.hotesses?.prenom || "?", photo: c.hotesses?.photos?.[0] || null,
      date: c.missions?.date, heure_debut: c.missions?.heure_debut, heure_fin: c.missions?.heure_fin
    }));
  } else {
    const { data: cands } = await db.from("candidatures")
      .select("mission_id, hotesse_id, missions(date, heure_debut, heure_fin, etablissements(nom, photos))")
      .eq("hotesse_id", user.id)
      .in("statut", ["acceptee", "confirmee"])
      .eq("annulation", false);
    return (cands || []).map(c => ({
      mission_id: c.mission_id, hotesse_id: c.hotesse_id,
      nom: c.missions?.etablissements?.nom || "?", photo: c.missions?.etablissements?.photos?.[0] || null,
      date: c.missions?.date, heure_debut: c.missions?.heure_debut, heure_fin: c.missions?.heure_fin
    }));
  }
}

async function afficherMessages(conteneurId) {
  const zone = document.getElementById(conteneurId || "messages");
  if (!zone) return;
  zone.innerHTML = '<div class="vide">Chargement…</div>';
  const convs = await _mesConversations();
  if (!convs.length) { zone.innerHTML = '<div class="vide">Aucune conversation pour le moment.</div>'; return; }

  // dernier message + non-lus par conversation
  const infos = await Promise.all(convs.map(async (c) => {
    const { data: msgs } = await db.from("messages")
      .select("contenu, created_at, expediteur_id, lu_a")
      .eq("mission_id", c.mission_id).eq("hotesse_id", c.hotesse_id)
      .order("created_at", { ascending: false }).limit(30);
    const dernier = msgs?.[0];
    const { data: { user } } = await auth.getUser();
    const nonLus = (msgs || []).filter(m => m.expediteur_id !== user.id && !m.lu_a).length;
    return { ...c, dernier, nonLus };
  }));

  zone.innerHTML = infos.map(c => {
    const photo = urlPhoto(c.photo);
    const d = c.date ? new Date(c.date).toLocaleDateString("fr-FR", { day: "numeric", month: "short" }) : "";
    return `<div style="display:flex;align-items:center;gap:12px;padding:12px 0;border-bottom:1px solid #F1E9DA;cursor:pointer" onclick="ouvrirConversation('${c.mission_id}','${c.hotesse_id}','${esc(c.nom)}','${(c.photo||"").replace(/'/g,"")}')">
      <div style="width:48px;height:48px;border-radius:50%;overflow:hidden;background:var(--champagne);flex-shrink:0">${photo ? `<img src="${photo}" style="width:100%;height:100%;object-fit:cover">` : ""}</div>
      <div style="flex:1;min-width:0">
        <div style="display:flex;justify-content:space-between"><b style="font-size:14px">${esc(c.nom)}</b>${d ? `<span style="font-size:11px;color:var(--gris)">${d}</span>` : ""}</div>
        <div style="font-size:12.5px;color:var(--gris);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${c.dernier ? esc(c.dernier.contenu || "📷 photo") : "Nouvelle conversation"}</div>
      </div>
      ${c.nonLus ? `<span style="background:var(--aubergine);color:#fff;border-radius:999px;min-width:20px;height:20px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:600;padding:0 6px">${c.nonLus}</span>` : ""}
    </div>`;
  }).join("");
}

async function ouvrirConversation(missionId, hotesseId, nom, photo) {
  _convOuverte = { mission_id: missionId, hotesse_id: hotesseId, nom, photo };
  const modal = document.createElement("div");
  modal.id = "modal-conversation";
  modal.style.cssText = "position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:flex-end;justify-content:center;z-index:996";
  modal.innerHTML = `
    <div style="background:#fff;border-radius:18px 18px 0 0;width:100%;max-width:430px;max-height:92vh;display:flex;flex-direction:column">
      <div style="display:flex;align-items:center;gap:10px;padding:14px 16px;border-bottom:1px solid #F1E9DA">
        <button style="background:none;border:none;font-size:20px;cursor:pointer" onclick="fermerConversation()">‹</button>
        <b style="flex:1">${esc(nom)}</b>
        <button style="background:none;border:none;font-size:16px" onclick="signalerConversation()">🚩</button>
      </div>
      <div style="padding:10px 16px;background:#FBF6EC;font-size:11.5px;color:var(--gris)">Pour ta sécurité, les numéros de téléphone et les réseaux sociaux sont bloqués.</div>
      <div id="conv-zone" style="flex:1;overflow-y:auto;padding:14px 16px;display:flex;flex-direction:column;gap:8px;min-height:200px">Chargement…</div>
      <div style="display:flex;gap:8px;padding:12px 16px;border-top:1px solid #F1E9DA">
        <input class="field" id="conv-saisie" placeholder="Écris un message…" style="flex:1" onkeydown="if(event.key==='Enter')envoyerMessage()">
        <button class="btn btn-primaire btn-sm" onclick="envoyerMessage()">Envoyer</button>
      </div>
    </div>`;
  document.body.appendChild(modal);
  chargerConversation();
}

async function chargerConversation() {
  if (!_convOuverte) return;
  const { data: { user } } = await auth.getUser();
  const zone = document.getElementById("conv-zone");
  if (!zone) return;
  const { data: msgs } = await db.from("messages")
    .select("*").eq("mission_id", _convOuverte.mission_id).eq("hotesse_id", _convOuverte.hotesse_id)
    .order("created_at", { ascending: true });
  // marque lu
  await db.from("messages").update({ lu_a: new Date().toISOString() })
    .eq("mission_id", _convOuverte.mission_id).eq("hotesse_id", _convOuverte.hotesse_id)
    .eq("destinataire_id", user.id).is("lu_a", null);
  const moi = (m) => m.expediteur_id === user.id;
  const dernierMoi = [...(msgs || [])].reverse().find(m => moi(m));
  // résout les URL signées des photos d'avance
  const urlPhotoMsg = {};
  for (const m of (msgs || [])) {
    if (m.photo_url && !urlPhotoMsg[m.id]) urlPhotoMsg[m.id] = await urlSignee(m.photo_url);
  }
  zone.innerHTML = (msgs && msgs.length) ? msgs.map((m, i) => {
    const dern = dernierMoi && m.id === dernierMoi.id;
    return `<div style="display:flex;justify-content:${moi(m) ? "flex-end" : "flex-start"}">
      <div style="max-width:75%;background:${moi(m) ? "var(--aubergine)" : "#F4E8D6"};color:${moi(m) ? "#fff" : "var(--aubergine)"};border-radius:14px;padding:9px 13px;font-size:13.5px;white-space:pre-line">${esc(m.contenu || "")}${m.photo_url ? `<br><img src="${urlPhotoMsg[m.id] || ""}" style="max-width:180px;border-radius:10px;margin-top:6px">` : ""}
        ${dernierMoi && dern ? `<div style="font-size:10px;opacity:.7;text-align:right;margin-top:3px">${m.lu_a ? "Vu" : "Envoyé"}</div>` : ""}
      </div>
    </div>`;
  }).join("") : '<div class="vide" style="width:100%">Commencez la conversation.</div>';
  // abonnement temps réel
  if (_canalMessages) { await db.removeChannel(_canalMessages); }
  _canalMessages = db.channel("messages-" + _convOuverte.mission_id + "-" + _convOuverte.hotesse_id)
    .on("postgres_changes", { event: "*", schema: "public", table: "messages", filter: `mission_id=eq.${_convOuverte.mission_id}` }, () => chargerConversation())
    .subscribe();
}

async function urlSignee(chemin) {
  try {
    const { data } = await sb.storage.from("messages").createSignedUrl(chemin, 300);
    return data?.signedUrl || "";
  } catch (e) { return ""; }
}

async function envoyerMessage() {
  const inp = document.getElementById("conv-saisie");
  const txt = (inp?.value || "").trim();
  if (!txt || !_convOuverte) return;
  const { error } = await db.from("messages").insert({
    mission_id: _convOuverte.mission_id, hotesse_id: _convOuverte.hotesse_id, contenu: txt
  });
  if (error) { toast(messageErreur(error), "erreur"); return; }
  if (inp) inp.value = "";
  chargerConversation();
}

function fermerConversation() {
  document.getElementById("modal-conversation")?.remove();
  if (_canalMessages) { db.removeChannel(_canalMessages); _canalMessages = null; }
  _convOuverte = null;
}

function signalerConversation() {
  if (!_convOuverte) return;
  toast("Signalement envoyé à DamUp (à compléter dans le profil).");
  fermerConversation();
}

async function ouvrirMessages() {
  const modal = document.createElement("div");
  modal.id = "modal-messages";
  modal.style.cssText = "position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:flex-end;justify-content:center;z-index:995";
  modal.innerHTML = `<div style="background:#fff;border-radius:18px 18px 0 0;width:100%;max-width:430px;max-height:90vh;overflow-y:auto;padding:16px">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px"><h3 style="font-family:var(--font-titre);font-size:18px">💬 Messages</h3><button style="background:none;border:none;font-size:20px;cursor:pointer" onclick="document.getElementById('modal-messages').remove()">✕</button></div>
    <div id="messages"></div></div>`;
  document.body.appendChild(modal);
  afficherMessages("messages");
}
