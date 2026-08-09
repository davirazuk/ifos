// Deliberately no caching: this app shows live download/queue state, so a
// stale cache would be worse than no service worker. It exists only to
// satisfy the browser's "installable web app" requirement.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
self.addEventListener("fetch", (event) => {
  event.respondWith(fetch(event.request));
});
