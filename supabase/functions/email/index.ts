// ============================================================
//  DamUp : Edge Function "email" — envoi d'e-mails selon modèles
//  Modèles pro (fond ivoire, titres aubergine, bouton aubergine).
//  Vouvoiement pour tout le monde. Fermée au public (x-damup-secret).
// ============================================================

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";
const SENDER_EMAIL = Deno.env.get("SENDER_EMAIL") ?? "";
const SENDER_NAME = "DamUp";

type Modele = { objet: string; corps: string; cat: "compte" | "moderation" | "missions" | "securite" };

// [BOUTON:texte] → bouton vers {lien}
// {variable} → remplacé
// rôle "commun" = même texte quel que soit le destinataire
const MODELES: Record<string, Partial<Record<"hotesse" | "etablissement" | "commun", Modele>>> = {
  // ============ 1. Comptes ============
  inscription: {
    hotesse: { cat: "compte", objet: "Bienvenue sur DamUp, {prenom}", corps: `<p>Bonjour {prenom},</p><p>Votre compte DamUp est créé. Il vous reste une étape avant de postuler aux missions : la vérification de votre identité (pièce d'identité + 18 ans minimum). Elle prend généralement moins de 24 h.</p><p>[BOUTON:Compléter mon profil]</p><p>En attendant, vous pouvez déjà ajouter vos photos et votre présentation : les établissements regardent d'abord les profils complets.</p>` },
    etablissement: { cat: "compte", objet: "Bienvenue sur DamUp, {nom_etablissement}", corps: `<p>Bonjour {prenom},</p><p>Le compte de {nom_etablissement} est créé. Nous vérifions chaque établissement avant la première publication : vous recevrez une confirmation sous 48 h.</p><p>Dès la validation, vous pourrez publier une mission en deux minutes : date, horaires, lieu, avantages offerts (boissons, entrée, plat, dessert, chicha).</p><p>[BOUTON:Accéder à mon tableau de bord]</p>` },
  },
  confirmation_email: {
    commun: { cat: "compte", objet: "Confirmez votre adresse e-mail", corps: `<p>Bonjour {prenom},</p><p>Cliquez sur le bouton ci-dessous pour confirmer votre adresse et activer votre compte DamUp.</p><p>[BOUTON:Confirmer mon adresse]</p><p>Ce lien est valable 24 h. Si vous n'êtes pas à l'origine de cette inscription, ignorez simplement ce message.</p>` },
  },
  identite_validee: {
    hotesse: { cat: "compte", objet: "Votre profil est vérifié", corps: `<p>Bonjour {prenom},</p><p>Bonne nouvelle : votre identité est vérifiée. Votre profil porte désormais le badge « Vérifié » et vous pouvez postuler à toutes les missions.</p><p>[BOUTON:Voir les missions]</p>` },
  },
  identite_refusee: {
    hotesse: { cat: "compte", objet: "Nous n'avons pas pu vérifier votre identité", corps: `<p>Bonjour {prenom},</p><p>Nous n'avons pas pu valider votre vérification d'identité pour la raison suivante : {motif}.</p><p>Vous pouvez renvoyer vos documents directement depuis votre profil. Pensez à une photo nette, sans reflet, avec les quatre coins visibles.</p><p>[BOUTON:Renvoyer mes documents]</p><p>Une question ? Répondez simplement à ce mail.</p>` },
  },
  etablissement_valide: {
    etablissement: { cat: "compte", objet: "{nom_etablissement} est validé sur DamUp", corps: `<p>Bonjour {prenom},</p><p>{nom_etablissement} est vérifié. Vous pouvez publier votre première mission dès maintenant.</p><p>[BOUTON:Publier une mission]</p>` },
  },
  etablissement_refuse: {
    etablissement: { cat: "compte", objet: "Nous n'avons pas pu valider {nom_etablissement}", corps: `<p>Bonjour {prenom},</p><p>Nous n'avons pas pu vérifier {nom_etablissement} : {motif}.</p><p>Merci de nous envoyer un justificatif (extrait Kbis, licence ou facture récente au nom de l'établissement) en réponse à ce mail ; nous reprendrons la vérification sous 48 h.</p>` },
  },
  rappel_photos: {
    commun: { cat: "compte", objet: "Votre profil DamUp a besoin de vos photos", corps: `<p>Bonjour {prenom},</p><p>Votre profil DamUp n'a pas encore assez de photos. Ajoutez au moins 4 photos de bonne qualité pour pouvoir postuler aux missions : sans elles, les établissements ne verront pas vos candidatures.</p><p>[BOUTON:Ajouter mes photos]</p><p>Les profils complets sont les premiers choisis.</p>` },
  },

  // ============ 2. Modération ============
  avertissement: {
    commun: { cat: "moderation", objet: "Un rappel concernant votre compte DamUp", corps: `<p>Bonjour {prenom},</p><p>Nous avons reçu un signalement concernant {motif}. Votre compte reste actif, mais nous tenions à vous le signaler : un nouveau manquement pourrait entraîner une suspension.</p><p>Pour rappel, les règles DamUp sont simples : respect des conditions de mission acceptées, ponctualité, et comportement correct envers chacun.</p><p>Si vous pensez qu'il s'agit d'une erreur, répondez à ce mail et nous regarderons ensemble.</p>` },
  },
  suspension: {
    commun: { cat: "moderation", objet: "Votre compte DamUp est suspendu", corps: `<p>Bonjour {prenom},</p><p>Votre compte est suspendu pour le motif suivant : {motif}.</p><p>Pendant cette période :</p><ul><li>vous ne pouvez plus postuler ni publier de mission ;</li><li>vos missions déjà confirmées sont annulées et les personnes concernées sont prévenues ;</li><li>votre profil n'est plus visible.</li></ul><p>Pour contester cette décision, répondez à ce mail sous 7 jours.</p>` },
  },
  reactivation: {
    commun: { cat: "moderation", objet: "Votre compte DamUp est de nouveau actif", corps: `<p>Bonjour {prenom},</p><p>Votre suspension est terminée : votre compte est réactivé et votre profil est de nouveau visible.</p><p>[BOUTON:Me connecter]</p>` },
  },
  suppression_damup: {
    commun: { cat: "moderation", objet: "Votre compte DamUp a été supprimé", corps: `<p>Bonjour {prenom},</p><p>Votre compte DamUp a été définitivement supprimé pour le motif suivant : {motif}.</p><p>Cette décision est irréversible. Votre profil, vos missions, vos candidatures et vos notifications ont été effacés. Vos données personnelles sont supprimées conformément à notre politique de confidentialité ; seules celles que la loi nous oblige à conserver sont gardées, le temps légal.</p><p>Si vous estimez qu'il s'agit d'une erreur, vous pouvez nous écrire à contact@damup.fr.</p>` },
  },
  suppression_utilisateur: {
    commun: { cat: "moderation", objet: "Votre compte DamUp est supprimé", corps: `<p>Bonjour {prenom},</p><p>Comme demandé, votre compte DamUp est supprimé. Votre profil, vos missions et vos candidatures ont été effacés.</p><p>Merci d'avoir fait partie de DamUp. Si vous changez d'avis, vous pourrez créer un nouveau compte à tout moment sur damup.fr.</p>` },
  },

  // ============ 3. Missions — hôtesse ============
  candidature_envoyee: {
    hotesse: { cat: "missions", objet: "Candidature envoyée — {titre_mission}", corps: `<p>Bonjour {prenom},</p><p>Votre candidature pour « {titre_mission} » chez {nom_etablissement} ({date_mission}) est bien envoyée. L'établissement vous répond généralement sous 48 h.</p><p>[BOUTON:Suivre ma candidature]</p>` },
  },
  candidature_acceptee: {
    hotesse: { cat: "missions", objet: "C'est oui ! Vous êtes retenue pour {titre_mission}", corps: `<p>Bonjour {prenom},</p><p>{nom_etablissement} vous a sélectionnée pour la mission « {titre_mission} ».</p><p>Récapitulatif :</p><ul><li>Date : {date_mission}</li><li>Horaires : {horaires}</li><li>Adresse : {adresse}</li><li>Avantages offerts : {avantages}</li></ul><p>Merci de confirmer votre présence depuis l'application. Un empêchement ? Prévenez au plus tôt : une annulation à moins de 24 h est signalée sur votre profil.</p><p>[BOUTON:Confirmer ma présence]</p>` },
  },
  candidature_refusee: {
    hotesse: { cat: "missions", objet: "Réponse pour {titre_mission}", corps: `<p>Bonjour {prenom},</p><p>{nom_etablissement} n'a pas retenu votre candidature pour « {titre_mission} » cette fois-ci. Cela n'a rien de définitif : de nouvelles missions sont publiées chaque jour.</p><p>[BOUTON:Voir les missions du moment]</p>` },
  },
  rappel_veille: {
    hotesse: { cat: "missions", objet: "Demain : {titre_mission} chez {nom_etablissement}", corps: `<p>Bonjour {prenom},</p><p>Petit rappel : votre mission « {titre_mission} » a lieu demain.</p><ul><li>Horaires : {horaires}</li><li>Adresse : {adresse}</li><li>Contact sur place : disponible dans l'application</li></ul><p>Pensez à votre pièce d'identité et à arriver 10 minutes en avance.</p><p>[BOUTON:Voir les détails]</p><p>Bonne soirée,</p>` },
  },
  mission_annulee: {
    hotesse: { cat: "missions", objet: "Mission annulée — {titre_mission}", corps: `<p>Bonjour {prenom},</p><p>{nom_etablissement} a annulé la mission « {titre_mission} » prévue le {date_mission}. Nous sommes désolés pour ce contretemps.</p><p>Cette annulation n'a aucun impact sur votre profil. D'autres missions vous attendent :</p><p>[BOUTON:Voir les missions]</p>` },
  },
  mission_terminee: {
    hotesse: { cat: "missions", objet: "Merci pour votre mission chez {nom_etablissement}", corps: `<p>Bonjour {prenom},</p><p>Votre mission « {titre_mission} » est terminée et ajoutée à votre historique. {nom_etablissement} peut maintenant vous laisser un avis, visible sur votre profil.</p><p>Un problème pendant la soirée ? Vous pouvez le signaler depuis la fiche de la mission.</p><p>[BOUTON:Voir mon historique]</p>` },
  },
  copine_invitee: {
    hotesse: { cat: "missions", objet: "{prenom} vous propose de rejoindre DamUp", corps: `<p>Bonjour,</p><p>{prenom} pense que DamUp pourrait vous plaire : des missions d'hôtesse de table dans des bars, restaurants et clubs, à choisir selon vos disponibilités.</p><p>L'inscription est gratuite et prend cinq minutes.</p><p>[BOUTON:Créer mon profil]</p>` },
  },

  // ============ 4. Missions — établissement ============
  mission_publiee: {
    etablissement: { cat: "missions", objet: "Votre mission « {titre_mission} » est en ligne", corps: `<p>Bonjour {prenom},</p><p>La mission « {titre_mission} » du {date_mission} est publiée et visible par les hôtesses vérifiées. Vous recevrez un e-mail à chaque nouvelle candidature.</p><p>[BOUTON:Gérer la mission]</p>` },
  },
  nouvelle_candidature: {
    etablissement: { cat: "missions", objet: "Nouvelle candidature pour {titre_mission}", corps: `<p>Bonjour {prenom},</p><p>Une hôtesse vient de postuler à « {titre_mission} » ({date_mission}). Consultez son profil, ses photos et ses avis, puis acceptez ou déclinez en un geste.</p><p>[BOUTON:Voir la candidature]</p>` },
  },
  presence_confirmee: {
    etablissement: { cat: "missions", objet: "{prenom_hotesse} a confirmé sa présence", corps: `<p>Bonjour {prenom},</p><p>{prenom_hotesse} confirme sa présence pour « {titre_mission} » le {date_mission} à {horaires}. Son contact est disponible dans votre tableau de bord.</p><p>[BOUTON:Voir la mission]</p>` },
  },
  desistement: {
    etablissement: { cat: "missions", objet: "Désistement pour {titre_mission}", corps: `<p>Bonjour {prenom},</p><p>{prenom_hotesse} ne pourra pas assurer la mission « {titre_mission} » du {date_mission}. Sa place est de nouveau ouverte et les autres candidates restent disponibles.</p><p>[BOUTON:Choisir une autre hôtesse]</p>` },
  },
  rappel_avis: {
    etablissement: { cat: "missions", objet: "Comment s'est passée la soirée avec {prenom_hotesse} ?", corps: `<p>Bonjour {prenom},</p><p>La mission « {titre_mission} » est terminée. Laissez un avis sur {prenom_hotesse} : cela prend 30 secondes et aide les autres établissements à choisir.</p><p>[BOUTON:Laisser un avis]</p><p>Merci,</p>` },
  },
  fin_essai: {
    etablissement: { cat: "missions", objet: "Votre essai DamUp se termine dans 3 jours", corps: `<p>Bonjour {prenom},</p><p>Votre essai gratuit se termine le {date_fin_essai}. Pour continuer à publier des missions et consulter les profils, choisissez votre abonnement.</p><p>[BOUTON:Choisir mon abonnement]</p><p>Sans action de votre part, vos missions en ligne resteront visibles jusqu'à leur date, mais vous ne pourrez plus en publier de nouvelles.</p>` },
  },
  paiement_echoue: {
    etablissement: { cat: "missions", objet: "Problème de paiement sur votre abonnement DamUp", corps: `<p>Bonjour {prenom},</p><p>Le prélèvement de votre abonnement n'a pas abouti. Merci de mettre à jour votre moyen de paiement sous 7 jours pour conserver l'accès à votre tableau de bord.</p><p>[BOUTON:Mettre à jour mon paiement]</p>` },
  },
  facture: {
    etablissement: { cat: "missions", objet: "Votre facture DamUp de {mois}", corps: `<p>Bonjour {prenom},</p><p>Votre facture de {mois} pour {nom_etablissement} est disponible en pièce jointe et dans votre espace.</p><p>[BOUTON:Voir mes factures]</p>` },
  },

  // ============ 5. Sécurité et signalements ============
  code_connexion: {
    commun: { cat: "securite", objet: "{code} est votre code DamUp", corps: `<p>Bonjour {prenom},</p><p>Voici votre code de connexion : <strong>{code}</strong></p><p>Il est valable 10 minutes. Ne le partagez avec personne : DamUp ne vous le demandera jamais par téléphone ou par message.</p><p>Si vous n'êtes pas à l'origine de cette connexion, changez votre mot de passe dès maintenant.</p>` },
  },
  reinitialiser_mdp: {
    commun: { cat: "securite", objet: "Réinitialisez votre mot de passe DamUp", corps: `<p>Bonjour {prenom},</p><p>Vous avez demandé à changer votre mot de passe. Cliquez sur le bouton ci-dessous pour en choisir un nouveau.</p><p>[BOUTON:Choisir un nouveau mot de passe]</p><p>Ce lien expire dans 1 heure. Si vous n'avez rien demandé, ignorez ce mail : votre mot de passe actuel reste valable.</p>` },
  },
  mdp_modifie: {
    commun: { cat: "securite", objet: "Votre mot de passe a été modifié", corps: `<p>Bonjour {prenom},</p><p>Votre mot de passe DamUp vient d'être modifié. Si c'est vous, tout est en ordre.</p><p>Si ce n'est pas vous, écrivez-nous immédiatement à contact@damup.fr pour sécuriser votre compte.</p>` },
  },
  nouvel_appareil: {
    commun: { cat: "securite", objet: "Nouvelle connexion à votre compte DamUp", corps: `<p>Bonjour {prenom},</p><p>Une connexion à votre compte vient d'avoir lieu depuis un nouvel appareil ({appareil}, {ville}, le {date} à {heure}).</p><p>Si c'est vous, vous pouvez ignorer ce message. Sinon, changez votre mot de passe sans attendre.</p><p>[BOUTON:Sécuriser mon compte]</p>` },
  },
  signalement_recu: {
    commun: { cat: "securite", objet: "Nous avons bien reçu votre signalement", corps: `<p>Bonjour {prenom},</p><p>Merci pour votre signalement concernant {objet_signalement}. Notre équipe l'examine sous 48 h et vous tient informé de la suite.</p><p>Vos échanges avec nous restent confidentiels. Si vous êtes en danger, contactez immédiatement les secours (17 ou 112).</p>` },
  },
  signalement_traite: {
    commun: { cat: "securite", objet: "Suite de votre signalement", corps: `<p>Bonjour {prenom},</p><p>Nous avons traité votre signalement concernant {objet_signalement}. Les mesures nécessaires ont été prises conformément à nos règles. Par respect de la confidentialité, nous ne pouvons pas détailler les actions menées sur un autre compte.</p><p>Merci de contribuer à une communauté sûre.</p>` },
  },
  export_rgpd: {
    commun: { cat: "securite", objet: "Vos données DamUp sont prêtes", corps: `<p>Bonjour {prenom},</p><p>Comme demandé, voici l'export de vos données personnelles. Le lien est valable 7 jours.</p><p>[BOUTON:Télécharger mes données]</p>` },
  },
};

function echapper(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function construireHtml(corps: string, variables: Record<string, string>, avecLienNotif: boolean): string {
  // 1) remplacer les variables
  let c = corps;
  for (const [k, v] of Object.entries(variables)) {
    c = c.split(`{${k}}`).join(v ?? "");
  }
  // 2) boutons [BOUTON:texte] → lien {lien}
  const lien = variables["lien"] ?? "";
  c = c.replace(/\[BOUTON:([^\]]+)\]/g, (_m, texte: string) =>
    lien
      ? `<p style="margin:18px 0"><a href="${echapper(lien)}" style="display:inline-block;background:#2A1120;color:#E7CFA8;padding:12px 20px;border-radius:8px;text-decoration:none;font-weight:600;font-size:14px">${texte}</a></p>`
      : `<p style="margin:18px 0;font-weight:600">${texte}</p>`
  );

  const signature = `<p style="margin:22px 0 0">Bien cordialement,<br>L'équipe DamUp</p>`;

  const lienNotif = avecLienNotif
    ? ` · <a href="https://damup.fr" style="color:#8A6D3B">Gérer mes notifications</a>`
    : "";

  return `<!DOCTYPE html><html><body style="margin:0;padding:0;background:#F4E8D6">
<div style="background:#F4E8D6;padding:24px 12px">
  <div style="max-width:520px;margin:0 auto;background:#FFFDF8;border-radius:12px;border:1px solid #EDE3D0;overflow:hidden">
    <div style="background:#2A1120;padding:16px 24px">
      <span style="font-family:'Bodoni Moda',Georgia,serif;color:#E7CFA8;font-size:20px;letter-spacing:.5px">DamUp</span>
    </div>
    <div style="padding:24px;color:#2A1120;font-family:Jost,Arial,sans-serif;font-size:15px;line-height:1.6">
      ${c}
      ${signature}
    </div>
    <div style="background:#F4E8D6;padding:14px 24px;font-family:Jost,Arial,sans-serif;font-size:12px;color:#8A6D3B">
      DamUp · damup.fr · contact@damup.fr${lienNotif}
    </div>
  </div>
</div>
</body></html>`;
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200 });
  try {
    const secret = req.headers.get("x-damup-secret") ?? "";
    const attendu = Deno.env.get("NOTIFIER_SECRET") ?? "";
    if (!attendu || secret !== attendu) return json({ error: "Non autorisé" }, 401);

    const { evenement, email, role, variables } = await req.json() as any;
    if (!evenement || !email) return json({ error: "evenement et email requis" }, 400);
    if (!SENDER_EMAIL) return json({ error: "Expéditeur non configuré" }, 500);

    const modele = MODELES[evenement];
    if (!modele) return json({ error: "Modèle inconnu : " + evenement }, 400);
    const m = (modele as any)[role] ?? (modele as any).commun;
    if (!m) return json({ error: "Rôle inconnu pour ce modèle : " + role }, 400);

    const vars: Record<string, string> = variables ?? {};
    const html = construireHtml(m.corps, vars, m.cat === "missions");

    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "Content-Type": "application/json", "api-key": BREVO_API_KEY },
      body: JSON.stringify({
        sender: { name: SENDER_NAME, email: SENDER_EMAIL },
        replyTo: { email: "contact@damup.fr", name: "DamUp" },
        to: [{ email }],
        subject: construireHtml(m.objet, vars, false).replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim(),
        htmlContent: html,
      }),
    });
    const text = await res.text();
    return json({ ok: res.ok, message: res.ok ? "envoyé" : text });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
