// ============================================================
//  DamUp - solidité des mots de passe (S1)
// ============================================================

const MDP_COURANTS = ["azerty123!", "motdepasse1!", "password1!", "damup2026!", "qwertyuiop!", "1234567890", "abcdefghij", "azertyuiop", "motdepasse123"];

function verifierMotDePasse(mdp, opts) {
  opts = opts || {};
  const m = String(mdp || "");
  const regles = [
    { key: "longueur",  ok: m.length >= 10 },
    { key: "minuscule", ok: /[a-z]/.test(m) },
    { key: "majuscule", ok: /[A-Z]/.test(m) },
    { key: "chiffre",   ok: /[0-9]/.test(m) },
    { key: "symbole",   ok: /[^a-zA-Z0-9]/.test(m) },
  ];
  // pas de prénom / nom / e-mail (ni la partie avant le @)
  let personnel = true;
  const bas = m.toLowerCase();
  const interdits = [];
  if (opts.prenom) interdits.push(String(opts.prenom).toLowerCase());
  if (opts.nom) interdits.push(String(opts.nom).toLowerCase());
  if (opts.email) {
    interdits.push(String(opts.email).toLowerCase());
    const avant = String(opts.email).split("@")[0].toLowerCase();
    if (avant) interdits.push(avant);
  }
  for (const s of interdits) {
    if (s && s.length >= 3 && bas.includes(s)) { personnel = false; break; }
  }
  regles.push({ key: "personnel", ok: personnel });
  regles.push({ key: "courant", ok: !MDP_COURANTS.includes(bas) });

  const nbOk = regles.filter(r => r.ok).length;
  const ok = nbOk === regles.length;
  const score = ok ? 2 : (nbOk >= 5 ? 1 : 0);
  return { ok, score, regles };
}

function htmlIndicateurMdp(r) {
  const noms = [t("mdp.faible"), t("mdp.moyen"), t("mdp.fort")];
  const couleurs = ["#C0392B", "#E67E22", "#1E7A3C"];
  const labels = {
    longueur: t("mdp.regle_longueur"), minuscule: t("mdp.regle_minuscule"), majuscule: t("mdp.regle_majuscule"),
    chiffre: t("mdp.regle_chiffre"), symbole: t("mdp.regle_symbole"), personnel: t("mdp.regle_personnel"),
    courant: t("mdp.regle_courant"),
  };
  let html = `<div style="margin:8px 0 6px">
    <div style="height:6px;border-radius:3px;background:#EEE;overflow:hidden"><div style="height:100%;width:${(r.score + 1) * 33.3}%;background:${couleurs[r.score]};transition:width .2s"></div></div>
    <div style="font-size:12px;color:${couleurs[r.score]};margin-top:4px">${noms[r.score]}</div>
  </div>`;
  html += `<div style="font-size:12px;color:#8a8a8a;line-height:1.7">${r.regles.map(g => `<span style="display:inline-block;margin-right:8px;white-space:nowrap">${g.ok ? "✅" : "❌"} ${labels[g.key]}</span>`).join("")}</div>`;
  return html;
}

// branche l'indicateur sous un champ mot de passe + bouton 👁 + désactive le bouton tant que non valide
function brancherIndicateurMdp(inputEl, opts, boutonEl) {
  if (!inputEl) return;
  const zone = document.createElement("div");
  zone.id = "zone-mdp-" + inputEl.id;
  inputEl.parentNode.insertBefore(zone, inputEl.nextSibling);
  const eye = document.createElement("button");
  eye.type = "button";
  eye.textContent = "👁";
  eye.id = "oeil-mdp-" + inputEl.id;
  eye.style.cssText = "margin-left:6px;background:none;border:none;font-size:16px;cursor:pointer;vertical-align:middle";
  inputEl.parentNode.insertBefore(eye, inputEl.nextSibling);
  eye.onclick = () => { inputEl.type = inputEl.type === "password" ? "text" : "password"; };
  const maj = () => {
    const o = typeof opts === "function" ? (opts() || {}) : (opts || {});
    const r = verifierMotDePasse(inputEl.value, o);
    zone.innerHTML = htmlIndicateurMdp(r);
    if (boutonEl) boutonEl.disabled = !r.ok;
  };
  inputEl.addEventListener("input", maj);
  maj();
  return () => verifierMotDePasse(inputEl.value, typeof opts === "function" ? (opts() || {}) : (opts || {}));
}
