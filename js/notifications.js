// ============================================================
//  DamUp — notifications temps réel (in-app)
//  Écoute les changements Supabase (Realtime) et affiche une
//  alerte à l'utilisateur. Fonctionnel sans clé externe.
// ============================================================

// Hôtesse : alertée quand une de SES candidatures est acceptée/refusée.
function ecouterCandidaturesHotesse(userId) {
  return sb.channel("cand-" + userId)
    .on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "candidatures",
      filter: "hotesse_id=eq." + userId,
    }, (payload) => {
      const s = payload.new.statut;
      if (s === "acceptee") alert("🎉 Félicitations, tu as été acceptée à une mission !");
      else if (s === "refusee") alert("Ta candidature a été refusée.");
    })
    .subscribe();
}

// Établissement : alerté à chaque nouvelle candidature reçue.
function ecouterCandidaturesEtab() {
  return sb.channel("cand-nouvelles")
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "candidatures",
    }, () => {
      alert("📩 Nouvelle candidature reçue !");
    })
    .subscribe();
}
