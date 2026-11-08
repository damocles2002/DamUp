// ============================================================
//  DamUp — internationalisation (fr, en, es, zh)
//  Chargé AVANT les autres scripts. Fournit t(), langueCourante(),
//  le sélecteur de langue et la traduction des attributs data-i18n.
// ============================================================
const LANGUES = ["fr", "en", "es", "zh"];
const LANGUE_DEFAUT = "fr";
const NOMS_LANGUES = { fr: "FR", en: "EN", es: "ES", zh: "中文" };

// Dictionnaires chargés (indexés par code langue)
const _dico = { fr: {}, en: {}, es: {}, zh: {} };
let _charge = null;

function chargerDicts() {
  if (_charge) return _charge;
  _charge = Promise.all(LANGUES.map(l =>
    fetch("lang/" + l + ".json")
      .then(r => r.json())
      .then(d => { _dico[l] = d; })
      .catch(() => { console.warn("Dictionnaire introuvable : " + l); })
  )).then(() => {});
  return _charge;
}

function lireLangueStockee() { try { return localStorage.getItem("damup_langue"); } catch (e) { return null; } }
function ecrireLangueStockee(l) { try { localStorage.setItem("damup_langue", l); } catch (e) {} }

function langueNavigateur() {
  const n = String(navigator.language || "fr").toLowerCase();
  if (n.startsWith("fr")) return "fr";
  if (n.startsWith("en")) return "en";
  if (n.startsWith("es")) return "es";
  if (n.startsWith("zh")) return "zh";
  return LANGUE_DEFAUT;
}

let _langue = null;      // langue résolue (stockée ou navigateur)
let _langueCompte = null; // langue du compte, appliquée une fois connecté si rien de stocké

function langueCourante() {
  if (_langue) return _langue;
  const stockee = lireLangueStockee();
  _langue = (stockee && LANGUES.includes(stockee)) ? stockee : langueNavigateur();
  return _langue;
}

// Appelée après connexion : applique la langue du compte SI aucune langue stockée dans ce navigateur
function appliquerLangueCompte(langue) {
  if (lireLangueStockee()) return; // le choix du navigateur prime
  if (!LANGUES.includes(langue)) return;
  _langue = langue;
  appliquerLangueDOM();
}

function definirLangue(l) {
  if (!LANGUES.includes(l)) l = LANGUE_DEFAUT;
  _langue = l;
  ecrireLangueStockee(l);
  appliquerLangueDOM();
  if (typeof window.changerLangueCompte === "function") window.changerLangueCompte(l);
  if (typeof window.chargerPolicesChinoises === "function") window.chargerPolicesChinoises();
  (window._onLangueChange || []).forEach(fn => { try { fn(); } catch (e) {} });
  return l;
}

// Traduction d'une clé avec paramètres {nom}
function t(cle, params) {
  const langue = langueCourante();
  let texte = _dico[langue][cle];
  if (texte === undefined) texte = _dico[LANGUE_DEFAUT][cle];
  if (texte === undefined) { console.warn("Clé i18n manquante : " + cle); return cle; }
  if (params) for (const k in params) texte = texte.split("{" + k + "}").join(params[k] ?? "");
  return texte;
}

// Traduit les attributs data-i18n du document + <html lang> + <title>
function appliquerLangueDOM() {
  const langue = langueCourante();
  document.documentElement.lang = langue;
  const titreCle = document.documentElement.getAttribute("data-i18n-title");
  if (titreCle) document.title = t(titreCle);
  document.querySelectorAll("[data-i18n]").forEach(el => { el.textContent = t(el.getAttribute("data-i18n")); });
  document.querySelectorAll("[data-i18n-placeholder]").forEach(el => { el.placeholder = t(el.getAttribute("data-i18n-placeholder")); });
  document.querySelectorAll("[data-i18n-title]").forEach(el => { el.title = t(el.getAttribute("data-i18n-title")); });
  document.querySelectorAll("[data-i18n-aria-label]").forEach(el => { el.setAttribute("aria-label", t(el.getAttribute("data-i18n-aria-label"))); });
}

// Sélecteur de langue 🌐 FR ▾
function initSelecteurLangue(containerId) {
  const container = document.getElementById(containerId);
  if (!container) return;
  const rendre = () => {
    const cur = langueCourante();
    container.innerHTML = `
      <div style="position:relative;display:inline-block">
        <button id="btn-langue" style="display:flex;align-items:center;gap:4px;background:none;border:none;color:inherit;font-size:14px;font-weight:600;cursor:pointer;padding:4px 8px;font-family:inherit">🌐 ${NOMS_LANGUES[cur]} ▾</button>
        <div id="menu-langue" style="display:none;position:absolute;right:0;top:32px;background:#fff;color:#2A1120;border-radius:10px;box-shadow:0 8px 24px rgba(0,0,0,.22);z-index:70;min-width:112px;overflow:hidden">
          ${LANGUES.map(l => `<button data-lang="${l}" style="display:block;width:100%;text-align:left;padding:10px 14px;background:${l === cur ? "#F4E8D6" : "transparent"};border:none;font-size:14px;cursor:pointer;font-family:inherit">${NOMS_LANGUES[l]}</button>`).join("")}
        </div>
      </div>`;
    const btn = document.getElementById("btn-langue");
    const menu = document.getElementById("menu-langue");
    btn.onclick = (e) => { e.stopPropagation(); menu.style.display = menu.style.display === "block" ? "none" : "block"; };
    container.querySelectorAll("#menu-langue [data-lang]").forEach(b => {
      b.onclick = (e) => { e.stopPropagation(); definirLangue(b.dataset.lang); menu.style.display = "none"; };
    });
    document.addEventListener("click", () => { if (menu) menu.style.display = "none"; });
  };
  rendre();
}

// Polices chinoises chargées à la demande (L3)
function chargerPolicesChinoises() {
  if (langueCourante() !== "zh") return;
  if (document.getElementById("font-zh")) return;
  const link = document.createElement("link");
  link.id = "font-zh";
  link.rel = "stylesheet";
  link.href = "https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@300;400;500;700&family=Noto+Serif+SC:wght@400;600;700&display=swap";
  document.head.appendChild(link);
}

document.addEventListener("DOMContentLoaded", async () => {
  await chargerDicts();
  appliquerLangueDOM();
  chargerPolicesChinoises();
});
