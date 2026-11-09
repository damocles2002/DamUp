// ============================================================
//  DamUp - double vérification (TOTP) partagée
//  Aides pour inscrire / vérifier / désactiver un facteur TOTP.
// ============================================================

async function mfaActif() {
  const { data } = await auth.mfa.listFactors();
  return (data?.totp || []).some(f => f.status === "verified");
}

async function mfaEnroller() {
  const { data, error } = await auth.mfa.enroll({ factorType: "totp" });
  if (error) throw error;
  return data; // { id, totp: { qr_code, secret } }
}

async function mfaVerifier(factorId, code) {
  const { data: challenge, error } = await auth.mfa.challenge({ factorId });
  if (error) throw error;
  const { error: err } = await auth.mfa.verify({ factorId, challengeId: challenge.id, code });
  if (err) throw err;
  await auth.refreshSession();
}

async function mfaDesactiver() {
  const { data } = await auth.mfa.listFactors();
  for (const f of (data?.totp || [])) {
    if (f.status === "verified") await auth.mfa.unenroll({ factorId: f.id });
  }
}
