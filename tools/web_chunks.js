// Splits web/index.pck into content-defined chunks (web/chunks/<sha1>.bin) and writes web/pck.json, so a new web
// build only downloads the chunks that changed: chunk borders follow the bytes, not fixed offsets, so a file that
// grows or shrinks moves no other border (sw.js puts the pack back together from the browser cache and the network).
//   node tools/web_chunks.js [web dir]          (--stats <old pck> <new pck>: how much of the new one is reused)
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const MIN = 64 * 1024, AVG_BITS = 19, MAX = 2 * 1024 * 1024;   // ~0.5 MB chunks
const MASK = (1 << AVG_BITS) - 1;
const GEAR = new Uint32Array(256);
for (let i = 0, x = 0x9e3779b9; i < 256; i++) {   // a fixed pseudo-random table: the same borders on every machine
  x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0;
  GEAR[i] = x;
}

function chunks(buf) {
  const out = [];
  let start = 0;
  while (start < buf.length) {
    const end = Math.min(buf.length, start + MAX);
    let h = 0, i = start + MIN, cut = end;
    for (; i < end; i++) {
      h = ((h << 1) + GEAR[buf[i]]) >>> 0;
      if ((h & MASK) === 0) { cut = i + 1; break; }
    }
    out.push(buf.subarray(start, cut));
    start = cut;
  }
  return out;
}
const sha = (b) => crypto.createHash('sha1').update(b).digest('hex');

if (process.argv[2] === '--stats') {
  const a = new Set(chunks(fs.readFileSync(process.argv[3])).map(sha));
  const nb = chunks(fs.readFileSync(process.argv[4]));
  const fresh = nb.filter((c) => !a.has(sha(c)));
  const mb = (n) => (n / 1048576).toFixed(1);
  console.log(`${nb.length} chunks, ${fresh.length} new: ${mb(fresh.reduce((s, c) => s + c.length, 0))} of ${mb(nb.reduce((s, c) => s + c.length, 0))} MB`);
  process.exit(0);
}

const web = process.argv[2] || 'web';
const pck = fs.readFileSync(path.join(web, 'index.pck'));
const dir = path.join(web, 'chunks');
fs.mkdirSync(dir, { recursive: true });
const list = [];
for (const c of chunks(pck)) {
  const h = sha(c);
  const f = path.join(dir, h + '.bin');
  if (!fs.existsSync(f)) fs.writeFileSync(f, c);
  list.push([h, c.length]);
}
const keep = new Set(list.map(([h]) => h + '.bin'));
let removed = 0;
for (const f of fs.readdirSync(dir)) if (!keep.has(f)) { fs.unlinkSync(path.join(dir, f)); removed++; }
const wasm = fs.readFileSync(path.join(web, 'index.wasm'));
fs.writeFileSync(path.join(web, 'pck.json'), JSON.stringify({ size: pck.length, wasm: sha(wasm).slice(0, 12), chunks: list }));
fs.unlinkSync(path.join(web, 'index.pck'));   // the page reads the pack through sw.js; only the chunks are published
console.log(`pck ${(pck.length / 1048576).toFixed(1)} MB -> ${list.length} chunks (${removed} old removed)`);
