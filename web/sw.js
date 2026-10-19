// Keeps the web build in the browser cache and updates it incrementally.
// The resource pack is published as content-defined chunks (web/chunks/<sha1>.bin, listed in web/pck.json by
// tools/web_chunks.js): a new build changes only the chunks around the changed files, so a returning player
// downloads just those. index.pck is put back together here from the cached and the new chunks.
// The engine (index.wasm) is cached under its hash; the small files under the build id.
const BUILD = '587f143a73aa';
const STATIC = 'zmxy2-static-' + BUILD;
const CHUNKS = 'zmxy2-chunks';
const ENGINE = 'zmxy2-engine';
const SMALL = ['index.js', 'index.audio.worklet.js', 'index.audio.position.worklet.js',
	'loading_bg.png', 'loading_bar_empty.png', 'loading_bar_full.png'];

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		for (const k of await caches.keys()) {
			// the old whole-pack cache of earlier builds and the small files of older builds
			if ((k.startsWith('zmxy2-remake-') || k.startsWith('zmxy2-static-')) && k !== STATIC) await caches.delete(k);
		}
		await self.clients.claim();
	})());
});

const base = () => self.registration.scope;

async function manifest() {
	const res = await fetch(base() + 'pck.json', { cache: 'no-cache' });
	if (!res.ok) throw new Error('pck.json ' + res.status);
	return res.json();
}

// index.pck: a stream of the chunks in order, each from the cache or else the network (then cached)
async function pack() {
	const m = await manifest();
	const cache = await caches.open(CHUNKS);
	let i = 0;
	const body = new ReadableStream({
		async pull(ctl) {
			if (i >= m.chunks.length) {
				ctl.close();
				prune(cache, m).catch(() => {});
				return;
			}
			const [hash] = m.chunks[i++];
			const key = base() + 'chunks/' + hash + '.bin';
			let res = await cache.match(key);
			if (!res) {
				res = await fetch(key);
				if (!res.ok) throw new Error('chunk ' + hash + ' ' + res.status);
				await cache.put(key, res.clone());
			}
			ctl.enqueue(new Uint8Array(await res.arrayBuffer()));
		},
	});
	return new Response(body, { headers: { 'Content-Type': 'application/octet-stream', 'Content-Length': String(m.size) } });
}

// chunks no build uses any more
async function prune(cache, m) {
	const keep = new Set(m.chunks.map(([h]) => base() + 'chunks/' + h + '.bin'));
	for (const req of await cache.keys()) if (!keep.has(req.url)) await cache.delete(req);
}

async function engine(request) {
	const m = await manifest();
	const key = base() + 'index.wasm?' + m.wasm;
	const cache = await caches.open(ENGINE);
	const hit = await cache.match(key);
	if (hit) return hit;
	const res = await fetch(request);
	if (res.ok) {
		for (const old of await cache.keys()) await cache.delete(old);
		await cache.put(key, res.clone());
	}
	return res;
}

async function small(request, name) {
	const cache = await caches.open(STATIC);
	const hit = await cache.match(name);
	if (hit) return hit;
	const res = await fetch(request);
	if (res.ok) cache.put(name, res.clone()).catch(() => {});
	return res;
}

self.addEventListener('fetch', (event) => {
	const url = new URL(event.request.url);
	if (event.request.method !== 'GET' || url.origin !== location.origin || !url.href.startsWith(base())) return;
	const name = url.href.slice(base().length).split('?')[0];
	if (name === 'index.pck') event.respondWith(pack());
	else if (name === 'index.wasm') event.respondWith(engine(event.request));
	else if (SMALL.includes(name)) event.respondWith(small(event.request, name));
});
