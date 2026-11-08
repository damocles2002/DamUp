// ============================================================
//  DamUp — Proposition d'installation (PWA)
//  Android : beforeinstallprompt. iPhone : guide en 3 étapes.
// ============================================================
(function () {
  let deferredPrompt = null;
  const KEY = "damup_install_dismissed";

  function cache() {
    try { return parseInt(localStorage.getItem(KEY) || "0", 10) || 0; } catch (e) { return 0; }
  }
  function masque7j() {
    try { localStorage.setItem(KEY, String(Date.now() + 7 * 86400000)); } catch (e) {}
  }
  function dejaInstalle() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
  }
  function bandeau(html) {
    if (document.getElementById("install-bandeau")) return;
    const b = document.createElement("div");
    b.id = "install-bandeau";
    b.style.cssText = "position:fixed;left:0;right:0;bottom:0;background:#2A1120;color:#F4E8D6;padding:14px 16px;display:flex;align-items:center;gap:10px;z-index:900;box-shadow:0 -4px 16px rgba(0,0,0,.15);font-family:Jost,sans-serif";
    b.innerHTML = html;
    document.body.appendChild(b);
    return b;
  }

  function afficherAndroid() {
    const b = bandeau(`<span style="flex:1;font-size:14px">📲 Installe DamUp sur ton téléphone</span>
      <button id="btn-installer" style="background:#E7CFA8;color:#2A1120;border:none;border-radius:10px;padding:10px 14px;font-weight:600;font-size:14px;cursor:pointer">Installer</button>
      <button id="btn-plus-tard" style="background:none;border:none;color:#E7CFA8;font-size:13px;cursor:pointer">Plus tard</button>`);
    document.getElementById("btn-installer").onclick = async () => {
      if (deferredPrompt) { deferredPrompt.prompt(); await deferredPrompt.userChoice; deferredPrompt = null; }
      b.remove();
    };
    document.getElementById("btn-plus-tard").onclick = () => { masque7j(); b.remove(); };
  }

  function afficherIos() {
    const b = bandeau(`<span style="flex:1;font-size:13px">📲 Pour installer : Partager → Sur l'écran d'accueil → Ajouter</span>
      <button id="btn-plus-tard" style="background:none;border:none;color:#E7CFA8;font-size:13px;cursor:pointer">Plus tard</button>`);
    document.getElementById("btn-plus-tard").onclick = () => { masque7j(); b.remove(); };
  }

  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferredPrompt = e;
    if (dejaInstalle() || Date.now() < cache()) return;
    afficherAndroid();
  });

  // iPhone : pas de beforeinstallprompt → proposition après un délai
  setTimeout(() => {
    if (deferredPrompt || dejaInstalle() || Date.now() < cache()) return;
    if (/iphone|ipad|ipod/i.test(navigator.userAgent) && document.body) afficherIos();
  }, 4000);

  // appelée depuis le lien « Installer l'application » des profils
  window.demanderInstallation = function () {
    if (dejaInstalle()) { alert("DamUp est déjà installé."); return; }
    if (deferredPrompt) { deferredPrompt.prompt(); return; }
    afficherIos();
  };
})();
