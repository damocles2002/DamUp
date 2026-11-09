// ============================================================
//  DamUp — Service worker (application installable)
//  IMPORTANT : à chaque mise en ligne, augmenter VERSION.
// ============================================================
const VERSION = "damup-v9";

const ASSETS = [
  "./",
  "./index.html",
  "./css/style.css",
  "./js/config.js",
  "./js/supabase.js",
  "./js/ui.js",
  "./js/i18n.js",
  "./js/notifications.js",
  "./lang/fr.json",
  "./lang/en.json",
  "./lang/es.json",
  "./lang/zh.json",
  "./assets/logo-couronne.png"
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(VERSION).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  // Jamais de cache pour Supabase, Stripe, Brevo ni les fonctions Edge
  if (url.hostname.includes("supabase.co") || url.hostname.includes("stripe.com") || url.hostname.includes("brevo.com")) {
    return;
  }
  // HTML : réseau d'abord, cache en secours
  if (e.request.mode === "navigate") {
    e.respondWith(fetch(e.request).catch(() => caches.match("./index.html")));
    return;
  }
  // images, polices, fichiers statiques : cache d'abord
  if (e.request.method === "GET") {
    e.respondWith(
      caches.match(e.request).then((hit) => {
        if (hit) return hit;
        return fetch(e.request).then((resp) => {
          const copy = resp.clone();
          caches.open(VERSION).then((c) => c.put(e.request, copy));
          return resp;
        });
      })
    );
  }
});

// notifications push (bloc M2)
self.addEventListener("push", (event) => {
  let data = { titre: "DamUp", texte: "", url: "" };
  try { data = event.data ? event.data.json() : data; } catch (e) {}
  const options = {
    body: data.texte || "",
    icon: "assets/icon-192.png",
    badge: "assets/icon-192.png",
    data: { url: data.url || "" },
  };
  event.waitUntil(self.registration.showNotification(data.titre || "DamUp", options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "./";
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        c.focus();
        c.navigate(url);
        return;
      }
      return clients.openWindow(url);
    })
  );
});
