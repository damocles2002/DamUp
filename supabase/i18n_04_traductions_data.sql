-- ============================================================
--  DamUp : i18n L5 : remplissage de la table traductions
--  (clés notif.* + email.* dans les 4 langues)
-- ============================================================

insert into public.traductions (cle, langue, texte) values
-- acceptée
('notif.acceptee', 'fr', '🎉 Tu as été acceptée chez {lieu} pour le {date} ! Confirme ta venue avant le {heure}, sinon ta place sera libérée.'),
('notif.acceptee', 'en', '🎉 You have been accepted at {lieu} on {date}! Confirm you are coming before {heure}, otherwise your spot will be released.'),
('notif.acceptee', 'es', '🎉 ¡Te han aceptado en {lieu} el {date}! Confirma tu asistencia antes de las {heure} o tu plaza se liberará.'),
('notif.acceptee', 'zh', '🎉 您已被 {lieu} 选中，日期 {date}！请在 {heure} 前确认到场，否则名额将被释放。'),

-- refusée
('notif.refusee', 'fr', 'Ta candidature chez {lieu} pour le {date} n''a pas été retenue.'),
('notif.refusee', 'en', 'Your application at {lieu} on {date} was not selected.'),
('notif.refusee', 'es', 'Tu candidatura en {lieu} el {date} no ha sido seleccionada.'),
('notif.refusee', 'zh', '您报名 {lieu} 的场次（{date}）未被选中。'),

-- expirée
('notif.expiree', 'fr', '⏰ Tu n''as pas confirmé à temps ta mission chez {lieu} du {date} : ta place a été libérée.'),
('notif.expiree', 'en', '⏰ You did not confirm your booking at {lieu} on {date} in time: your spot has been released.'),
('notif.expiree', 'es', '⏰ No confirmaste a tiempo tu evento en {lieu} el {date}: tu plaza ha sido liberada.'),
('notif.expiree', 'zh', '⏰ 您未及时确认 {lieu} 的场次（{date}）：名额已释放。'),

-- confirmée (établissement)
('notif.confirmee_etab', 'fr', '✅ Une hôtesse a confirmé sa venue pour ta mission du {date}.'),
('notif.confirmee_etab', 'en', '✅ A hostess has confirmed she is coming for your booking on {date}.'),
('notif.confirmee_etab', 'es', '✅ Una azafata ha confirmado su asistencia a tu evento del {date}.'),
('notif.confirmee_etab', 'zh', '✅ 一位礼仪小姐已确认到场，场次日期 {date}。'),

-- rappel confirmation
('notif.rappel_confirmation', 'fr', '⏳ Rappel : confirme ta venue avant {heure}, sinon ta place sera libérée.'),
('notif.rappel_confirmation', 'en', '⏳ Reminder: confirm you are coming before {heure}, otherwise your spot will be released.'),
('notif.rappel_confirmation', 'es', '⏳ Recordatorio: confirma tu asistencia antes de las {heure} o tu plaza se liberará.'),
('notif.rappel_confirmation', 'zh', '⏳ 提醒：请在 {heure} 前确认到场，否则名额将被释放。'),

-- annulation (établissement)
('notif.annulation_etab', 'fr', '⚠️ Une hôtesse a annulé sa venue : une place se libère sur ta mission du {date}.'),
('notif.annulation_etab', 'en', '⚠️ A hostess cancelled: a spot has opened up for your booking on {date}.'),
('notif.annulation_etab', 'es', '⚠️ Una azafata ha cancelado: se libera una plaza para tu evento del {date}.'),
('notif.annulation_etab', 'zh', '⚠️ 一位礼仪小姐取消了：您的场次（{date}）有一个名额空出。'),

-- suspension hôtesse
('notif.suspension_hotesse', 'fr', '🚫 Compte suspendu automatiquement après {n} annulations. Contacte DamUp.'),
('notif.suspension_hotesse', 'en', '🚫 Account suspended automatically after {n} cancellations. Contact DamUp.'),
('notif.suspension_hotesse', 'es', '🚫 Cuenta suspendida automáticamente tras {n} cancelaciones. Contacta con DamUp.'),
('notif.suspension_hotesse', 'zh', '🚫 因 {n} 次取消，账户已被自动暂停。请联系 DamUp。'),

-- suspension admin
('notif.suspension_admin', 'fr', '🚫 Une hôtesse a été suspendue automatiquement ({n} annulations).'),
('notif.suspension_admin', 'en', '🚫 A hostess has been suspended automatically ({n} cancellations).'),
('notif.suspension_admin', 'es', '🚫 Una azafata ha sido suspendida automáticamente ({n} cancelaciones).'),
('notif.suspension_admin', 'zh', '🚫 一位礼仪小姐已被自动暂停（{n} 次取消）。'),

-- paiement offert
('notif.paiement_offert', 'fr', '🎁 DamUp t''offre l''accès jusqu''au {date}.'),
('notif.paiement_offert', 'en', '🎁 DamUp is giving you access until {date}.'),
('notif.paiement_offert', 'es', '🎁 DamUp te ofrece el acceso hasta el {date}.'),
('notif.paiement_offert', 'zh', '🎁 DamUp 免费赠送您使用权限至 {date}。'),

-- paiement reçu
('notif.paiement_recu', 'fr', '✅ Paiement reçu : ton abonnement DamUp est actif jusqu''au {date}.'),
('notif.paiement_recu', 'en', '✅ Payment received: your DamUp subscription is active until {date}.'),
('notif.paiement_recu', 'es', '✅ Pago recibido: tu suscripción a DamUp está activa hasta el {date}.'),
('notif.paiement_recu', 'zh', '✅ 已收到付款：您的 DamUp 订阅有效期至 {date}。'),

-- fin d'abonnement
('notif.fin_abonnement', 'fr', '⏳ Ton abonnement DamUp se termine le {date}. Pense à le renouveler.'),
('notif.fin_abonnement', 'en', '⏳ Your DamUp subscription ends on {date}. Remember to renew it.'),
('notif.fin_abonnement', 'es', '⏳ Tu suscripción a DamUp termina el {date}. Recuerda renovarla.'),
('notif.fin_abonnement', 'zh', '⏳ 您的 DamUp 订阅将于 {date} 到期。请记得续订。'),

-- fin d'abonnement admin
('notif.fin_abonnement_admin', 'fr', '💶 {n} abonnement(s) se terminent dans moins de 3 jours.'),
('notif.fin_abonnement_admin', 'en', '💶 {n} subscription(s) end in less than 3 days.'),
('notif.fin_abonnement_admin', 'es', '💶 {n} suscripción(es) terminan en menos de 3 días.'),
('notif.fin_abonnement_admin', 'zh', '💶 {n} 个订阅将在 3 天内到期。'),

-- signalement admin
('notif.signalement_admin', 'fr', '🚩 Nouveau signalement à traiter.'),
('notif.signalement_admin', 'en', '🚩 New report to handle.'),
('notif.signalement_admin', 'es', '🚩 Nueva denuncia por atender.'),
('notif.signalement_admin', 'zh', '🚩 有新的举报需要处理。'),

-- paiement échoué (client)
('notif.paiement_echoue', 'fr', '⚠️ Ton paiement n''est pas passé, mets à jour ton moyen de paiement.'),
('notif.paiement_echoue', 'en', '⚠️ Your payment failed. Please update your payment method.'),
('notif.paiement_echoue', 'es', '⚠️ Tu pago no se ha realizado. Actualiza tu método de pago.'),
('notif.paiement_echoue', 'zh', '⚠️ 付款失败。请更新您的付款方式。'),

-- paiement échoué (admin)
('notif.paiement_echoue_admin', 'fr', '⚠️ Un paiement Stripe a échoué (facture {ref}).'),
('notif.paiement_echoue_admin', 'en', '⚠️ A Stripe payment failed (invoice {ref}).'),
('notif.paiement_echoue_admin', 'es', '⚠️ Un pago de Stripe ha fallado (factura {ref}).'),
('notif.paiement_echoue_admin', 'zh', '⚠️ 一笔 Stripe 付款失败（账单 {ref}）。'),

-- contestation (admin)
('notif.contestation_admin', 'fr', '⚠️ Contestation Stripe détectée. Consulte ton tableau de bord Stripe.'),
('notif.contestation_admin', 'en', '⚠️ A Stripe dispute was detected. Check your Stripe dashboard.'),
('notif.contestation_admin', 'es', '⚠️ Se ha detectado una disputa en Stripe. Revisa tu panel de Stripe.'),
('notif.contestation_admin', 'zh', '⚠️ 检测到 Stripe 争议。请查看您的 Stripe 后台。'),

-- nouvelle candidature
('notif.nouvelle_candidature', 'fr', '📩 {prenom} a postulé à ta mission du {date}.'),
('notif.nouvelle_candidature', 'en', '📩 {prenom} applied to your mission on {date}.'),
('notif.nouvelle_candidature', 'es', '📩 {prenom} se inscribió a tu evento del {date}.'),
('notif.nouvelle_candidature', 'zh', '📩 {prenom} 报名了您 {date} 的场次。'),

-- refus de validation
('notif.validation_refusee', 'fr', 'Ton profil n''a pas été validé : {motif}. Corrige-le puis contacte-nous.'),
('notif.validation_refusee', 'en', 'Your profile was not approved: {motif}. Please fix it and contact us.'),
('notif.validation_refusee', 'es', 'Tu perfil no fue aprobado: {motif}. Corrígelo y contáctanos.'),
('notif.validation_refusee', 'zh', '您的资料未通过审核：{motif}。请修改后联系我们。'),

-- annulation de mission par l'admin
('notif.mission_annulee_admin', 'fr', 'Ta mission a été annulée par DamUp : {motif}.'),
('notif.mission_annulee_admin', 'en', 'Your mission was cancelled by DamUp: {motif}.'),
('notif.mission_annulee_admin', 'es', 'Tu evento fue cancelado por DamUp: {motif}.'),
('notif.mission_annulee_admin', 'zh', '您的场次已被 DamUp 取消：{motif}。'),

-- note de mission modifiée
('notif.mission_note_modifiee', 'fr', '📝 {lieu} a mis à jour les informations de ta mission du {date}.'),
('notif.mission_note_modifiee', 'en', '📝 {lieu} updated the information for your mission on {date}.'),
('notif.mission_note_modifiee', 'es', '📝 {lieu} actualizó la información de tu evento del {date}.'),
('notif.mission_note_modifiee', 'zh', '📝 {lieu} 更新了您 {date} 场次的信息。'),

-- nouveau message
('notif.message.nouveau', 'fr', '💬 {nom} t''a écrit un message.'),
('notif.message.nouveau', 'en', '💬 {nom} sent you a message.'),
('notif.message.nouveau', 'es', '💬 {nom} te ha enviado un mensaje.'),
('notif.message.nouveau', 'zh', '💬 {nom} 给您发了一条消息。'),

-- e-mail
('email.sujet', 'fr', 'DamUp : nouvelle notification'),
('email.sujet', 'en', 'DamUp : new notification'),
('email.sujet', 'es', 'DamUp : nueva notificación'),
('email.sujet', 'zh', 'DamUp : 新通知'),
('email.ouvrir', 'fr', 'Ouvrir DamUp'),
('email.ouvrir', 'en', 'Open DamUp'),
('email.ouvrir', 'es', 'Abrir DamUp'),
('email.ouvrir', 'zh', '打开 DamUp')
on conflict (cle, langue) do update set texte = excluded.texte;
