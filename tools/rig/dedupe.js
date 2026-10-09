// Identical PNGs (same md5) are stored once. Every extractor writes its textures next to the thing it builds, so the same
// image shows up under many rigs / UIs / levels; this pass moves each group of identical files to
// game/assets/shared/<md5>.png, rewrites the "res" paths of the *.json it was extracted into, and sends the copies
// (and their .import files) to the Recycle Bin. Run it after any extraction, then rebuild the rigs:
//   node tools/rig/dedupe.js [--dry]          then   bash tools/rig/rebuild_all.sh
// (batch.sh runs both for the rigs it builds.)
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');

const GAME = path.join(__dirname, '..', '..', 'game');
const ASSETS = path.join(GAME, 'assets');
const SHARED = path.join(ASSETS, 'shared');
const dry = process.argv.includes('--dry');

const pngs = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (p !== SHARED) walk(p); } else if (e.name.endsWith('.png')) pngs.push(p);
  }
})(ASSETS);

const groups = new Map();
for (const p of pngs) {
  const h = crypto.createHash('md5').update(fs.readFileSync(p)).digest('hex');
  (groups.get(h) || groups.set(h, []).get(h)).push(p);
}
const res = (p) => 'res://' + path.relative(GAME, p).split(path.sep).join('/');

const map = new Map();       // old res path -> shared res path
const trash = [];
for (const [h, list] of groups) {
  if (list.length < 2) continue;
  const dst = path.join(SHARED, h + '.png');
  if (!dry && !fs.existsSync(dst)) { fs.mkdirSync(SHARED, { recursive: true }); fs.copyFileSync(list[0], dst); }
  for (const p of list) {
    map.set(res(p), res(dst));
    trash.push(p);
    if (fs.existsSync(p + '.import')) trash.push(p + '.import');
  }
}
console.log(`${pngs.length} png, ${groups.size} distinct, ${trash.filter((t) => t.endsWith('.png')).length} files in ${[...groups.values()].filter((l) => l.length > 1).length} duplicate groups`);
if (dry || !map.size) process.exit(0);

// references in the extracted json (rig / ui / level / item data) and in text scenes and resources
let changed = 0;
const patch = (file) => {
  let s = fs.readFileSync(file, 'utf8');
  const out = s.replace(/res:\/\/assets\/[^"'\s)\]]+?\.png/g, (m) => map.get(m) || m);
  if (out !== s) { fs.writeFileSync(file, out); changed++; }
};
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (e.name !== '.godot') walk(p); } else if (/\.(json|tscn|tres|gd|cfg)$/.test(e.name)) patch(p);
  }
})(GAME);
console.log('rewrote', changed, 'files');

// copies -> Recycle Bin (one PowerShell for the whole list)
const list = path.join(require('os').tmpdir(), 'dedupe_trash.txt');
fs.writeFileSync(list, trash.join('\n'));
const ps = `Add-Type -AssemblyName Microsoft.VisualBasic; Get-Content -LiteralPath '${list}' -Encoding UTF8 | ForEach-Object { if (Test-Path -LiteralPath $_) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($_, 'OnlyErrorDialogs', 'SendToRecycleBin') } }`;
cp.execFileSync('powershell', ['-NoProfile', '-Command', ps], { stdio: 'inherit' });
console.log('moved', trash.length, 'files to the Recycle Bin');
