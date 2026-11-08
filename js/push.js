// ============================================================
//  DamUp — Notifications push + préférences de notification
// ============================================================
const VAPID_PUBLIC_KEY = "BK1pNFQi1ljU8t6-Yz2bXzIi92PyxSf76LqC5Rolg5lR4IGXySwoPjfpchytdXgjAyfQ_U7grHltk_q1FlsXQKQ";

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

async function demanderPermissionPush() {
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
    toast("Ton navigateur ne gère pas les notifications.", "erreur");
    return;
  }
  const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent);
  if (isIOS && !(window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true)) {
    toast("Installe d'abord DamUp sur l'écran d'accueil (Partager → Sur l'écran d'accueil), puis réessaie.");
    return;
  }
  try {
    const perm = await Notification.requestPermission();
    if (perm !== "granted") {
      toast("Notifications refusées. Tu peux les autoriser dans les réglages de ton navigateur.");
      return;
    }
    const reg = await navigator.serviceWorker.ready;
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY) });
    }
    const json = sub.toJSON();
    const { data: { user } } = await auth.getUser();
    if (!user) return;
    await db.from("appareils_push").upsert({
      user_id: user.id,
      endpoint: json.endpoint,
      p256dh: json.keys.p256dh,
      auth_cle: json.keys.auth,
      appareil: navigator.userAgent.slice(0, 200)
    }, { onConflict: "endpoint" });
    toast("Notifications activées ✅", "ok");
    chargerNotifications();
  } catch (e) {
    toast("Impossible d'activer les notifications : " + e.message, "erreur");
  }
}

async function desactiverPush() {
  try {
    const reg = await navigator.serviceWorker.ready;
    const sub = await reg.pushManager.getSubscription();
    if (sub) await sub.unsubscribe();
    const { data: { user } } = await auth.getUser();
    if (user) await db.from("appareils_push").delete().eq("user_id", user.id);
    toast("Notifications désactivées.");
    chargerNotifications();
  } catch (e) { toast(e.message, "erreur"); }
}

async function chargerNotifications(conteneurId) {
  const zone = document.getElementById(conteneurId || "notifications");
  if (!zone) return;
  const { data: { user } } = await auth.getUser();
  if (!user) return;
  let abonne = false;
  try {
    const reg = await navigator.serviceWorker.ready;
    abonne = !!(await reg.pushManager.getSubscription());
  } catch (e) {}
  const { data: pref } = await db.from("preferences_notif").select("*").eq("user_id", user.id).single();
  const p = pref || { push_actif: true, email_missions: true, email_messages: false, email_compte: true };
  zone.innerHTML = `
    <div class="pub"><h3>Notifications</h3>
      <div style="padding:4px 0 12px">
        ${abonne
          ? `<button class="btn btn-sm" style="background:#FBE4E1;color:var(--danger)" onclick="desactiverPush()">Désactiver les notifications sur ce téléphone</button>`
          : `<button class="btn btn-sm btn-primaire" onclick="demanderPermissionPush()">Activer les notifications sur ce téléphone</button>`}
      </div>
      <label style="display:flex;gap:8px;align-items:center;font-size:13.5px;padding:8px 0;border-top:1px solid #F1E9DA"><input type="checkbox" id="n-push" ${p.push_actif ? "checked" : ""}> Recevoir les notifications push</label>
      <label style="display:flex;gap:8px;align-items:center;font-size:13.5px;padding:8px 0;border-top:1px solid #F1E9DA"><input type="checkbox" id="n-email-missions" ${p.email_missions ? "checked" : ""}> E-mails : candidatures, délais et rappels</label>
      <label style="display:flex;gap:8px;align-items:center;font-size:13.5px;padding:8px 0;border-top:1px solid #F1E9DA"><input type="checkbox" id="n-email-messages" ${p.email_messages ? "checked" : ""}> E-mails : nouveaux messages</label>
      <label style="display:flex;gap:8px;align-items:center;font-size:13.5px;padding:8px 0;border-top:1px solid #F1E9DA"><input type="checkbox" id="n-email-compte" ${p.email_compte ? "checked" : ""}> E-mails : compte (validation, abonnement, suspension)</label>
      <button class="btn btn-primaire btn-block btn-sm" onclick="sauverNotifications()">Enregistrer</button>
    </div>`;
}

async function sauverNotifications() {
  const { data: { user } } = await auth.getUser();
  if (!user) return;
  const get = (id) => document.getElementById(id)?.checked;
  const { error } = await db.from("preferences_notif").upsert({
    user_id: user.id,
    push_actif: get("n-push"),
    email_missions: get("n-email-missions"),
    email_messages: get("n-email-messages"),
    email_compte: get("n-email-compte"),
    updated_at: new Date().toISOString()
  });
  if (error) { toast(error.message, "erreur"); return; }
  toast("Préférences enregistrées ✅", "ok");
}
