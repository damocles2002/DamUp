// ============================================================
//  DamUp — notifications (cloche + compteur temps réel)
//  Affiche une cloche 🔔 avec le nombre de notifications non lues.
//  Les notifications sont créées côté base (triggers SQL).
// ============================================================
let clocheUserId = null;

function initCloche(containerId, userId) {
  clocheUserId = userId;
  const container = document.getElementById(containerId);
  if (!container) return;

  container.innerHTML = `
    <div style="position:relative;cursor:pointer" id="cloche-wrap">
      <span style="font-size:21px">🔔</span>
      <span id="cloche-badge" style="position:absolute;top:-7px;right:-9px;background:var(--danger);color:#fff;font-size:10.5px;font-weight:700;min-width:17px;height:17px;border-radius:999px;display:none;align-items:center;justify-content:center;padding:0 4px">0</span>
      <div id="cloche-menu" style="display:none;position:absolute;right:0;top:34px;width:290px;max-height:70vh;overflow-y:auto;background:#fff;border-radius:14px;box-shadow:0 12px 34px rgba(0,0,0,.22);z-index:60;text-align:left"></div>
    </div>`;

  const badge = document.getElementById("cloche-badge");
  const menu = document.getElementById("cloche-menu");

  async function chargerCompteur() {
    const { count } = await db.from("notifications").select("id", { count: "exact", head: true })
      .eq("lu", false).eq("user_id", userId);
    badge.textContent = count || 0;
    badge.style.display = count > 0 ? "flex" : "none";
  }

  document.getElementById("cloche-wrap").addEventListener("click", async () => {
    if (menu.style.display === "block") { menu.style.display = "none"; return; }
    const { data } = await db.from("notifications").select("*").order("created_at", { ascending: false }).limit(20);
    if (!data || !data.length) {
      menu.innerHTML = '<div style="padding:16px;color:var(--gris);font-size:13px">Aucune notification</div>';
    } else {
      menu.innerHTML = data.map(n => {
        const estCopine = (n.cle || "").startsWith("copine.");
        return `<div style="padding:12px 14px;border-bottom:1px solid #F1E9DA;font-size:13.5px;${n.lu ? "" : "background:#FFF8EE;font-weight:500"}${estCopine ? ";cursor:pointer" : ""}"${estCopine ? ` onclick="location.href='hotesse.html#invitations'"` : ""}>${esc(n.message)}</div>`;
      }).join("") +
        `<div style="padding:10px;text-align:center"><a style="color:var(--aubergine);font-size:12.5px;font-weight:600;cursor:pointer" onclick="toutLu()">Tout marquer comme lu</a></div>`;
    }
    menu.style.display = "block";
  });

  // temps réel : nouvelle notification → on rafraîchit le compteur
  sb.channel("notif-" + userId)
    .on("postgres_changes", { event: "INSERT", schema: "public", table: "notifications", filter: "user_id=eq." + userId }, () => chargerCompteur())
    .subscribe();

  chargerCompteur();
}

function toutLu() {
  if (!clocheUserId) return;
  db.from("notifications").update({ lu: true }).eq("user_id", clocheUserId).eq("lu", false).then(() => {
    const menu = document.getElementById("cloche-menu");
    const badge = document.getElementById("cloche-badge");
    if (menu) menu.style.display = "none";
    if (badge) badge.style.display = "none";
  });
}
