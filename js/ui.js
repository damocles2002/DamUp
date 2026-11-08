// ============================================================
//  DamUp — UI partagée : toast + fenêtre de confirmation
//  Remplace toast() et await demander() du navigateur.
// ============================================================

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
