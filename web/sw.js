// Caches the web build on the player's machine: the engine and the 150 MB pack are downloaded once per build.
// BUILD is replaced by tools/export_web.sh with a hash of index.pck + index.wasm; a new build gets a new cache and the
// old one is deleted.
const BUILD = 'dc5ed957ca6a';
const CACHE = 'zmxy2-remake-' + BUILD;
const FILES = ['index.pck', 'index.wasm', 'index.js', 'index.audio.worklet.js', 'index.audio.position.worklet.js',
	'loading_bg.png', 'loading_bar_empty.png', 'loading_bar_full.png'];

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		for (const k of await caches.keys()) {
			if (k.startsWith('zmxy2-remake-') && k !== CACHE) await caches.delete(k);
		}
		await self.clients.claim();
	})());
});

self.addEventListener('fetch', (event) => {
	const url = new URL(event.request.url);
	const name = url.pathname.slice(url.pathname.lastIndexOf('/') + 1);
	if (event.request.method !== 'GET' || url.origin !== location.origin || !FILES.includes(name)) return;
	event.respondWith((async () => {
		const cache = await caches.open(CACHE);
		const hit = await cache.match(name);
		if (hit) return hit;
		const res = await fetch(event.request);
		if (res.ok) {
			// the clone is stored while the page reads the original stream (its progress bar keeps working)
			cache.put(name, res.clone()).catch((e) => console.warn('cache put failed', name, e));
		}
		return res;
	})());
});
