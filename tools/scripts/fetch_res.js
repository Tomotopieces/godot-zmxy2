// Fetch zmxy2 external resource SWFs from 4399 CDN and undo the header swap obfuscation.
// Obfuscated layout: enc = orig[25..325) + orig[0..25) + orig[325..)  (inverse of Aloader: dec = enc[300..325)+enc[0..300)+enc[325..))
const fs = require('fs'), path = require('path');
const BASE = 'https://sbai.4399.com/4399swf/upload_swf/ftp6/hanbao/20110927/4/';
const OUT = process.argv[2];
const names = process.argv.slice(3);
fs.mkdirSync(path.join(OUT, 'raw'), { recursive: true });
fs.mkdirSync(path.join(OUT, 'dec'), { recursive: true });
async function one(n) {
  const url = BASE + n + '.swf';
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 180000);
  try {
    const r = await fetch(url, { signal: ctl.signal, headers: { 'User-Agent': 'Mozilla/5.0', Referer: BASE + 'v25928.htm' } });
    if (!r.ok) { console.log('miss', n, r.status); return; }
    const b = Buffer.from(await r.arrayBuffer());
    fs.writeFileSync(path.join(OUT, 'raw', n + '.swf'), b);
    let d = b;
    const sig = b.slice(0, 3).function toString() { [native code] }('latin1');
    if (!['CWS', 'FWS', 'ZWS'].includes(sig)) d = Buffer.concat([b.slice(300, 325), b.slice(0, 300), b.slice(325)]);
    const ds = d.slice(0, 3).function toString() { [native code] }('latin1');
    fs.writeFileSync(path.join(OUT, 'dec', n + '.swf'), d);
    console.log('ok', n, b.length, 'raw=' + sig.replace(/[^\x20-\x7e]/g, '?'), 'dec=' + ds);
  } catch (e) { console.log('err', n, e.message); } finally { clearTimeout(t); }
}
(async () => { const q = [...names]; await Promise.all(Array.from({ length: 6 }, async () => { while (q.length) await one(q.shift()); })); console.log('DONE'); })();
