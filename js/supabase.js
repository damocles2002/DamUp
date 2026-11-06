// ============================================================
//  DamUp — client Supabase partagé
//  On crée UNE seule instance `sb`, réutilisée partout
//  (ne pas re-déclarer dans les autres pages).
// ============================================================
const sb = supabase.createClient(SB_URL, SB_KEY);

// Raccourcis fréquents
const auth = sb.auth;
const db = sb;
