// ============================================================
//  DamUp — client Supabase partagé
//  On crée UNE seule instance `sb`, réutilisée partout
//  (ne pas re-déclarer dans les autres pages).
// ============================================================
const sb = supabase.createClient(SB_URL, SB_KEY);

// Raccourcis fréquents
const auth = sb.auth;
const db = sb;

// --- Formatage partagé (affichage lisible) ---
function formatHeure(t) { if (!t) return ""; const [h, m] = t.split(":"); return `${+h}h${m}`; }
function formatDate(d) { return d ? new Date(d + "T12:00:00").toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" }) : ""; }
const LIBELLES_ARTICLES = { boisson: "Boisson", entree: "Entrée", plat: "Plat", dessert: "Dessert", chicha: "Chicha" };
