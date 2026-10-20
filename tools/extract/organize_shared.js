// Gives the md5-named textures that dedupe.js collects in game/assets/shared a readable name and a home:
//   - used by one thing only (one puppet, one UI panel, one level)  -> that thing's own tex/ folder
//   - used by several things of one kind                         -> assets/shared/<kind>/   (puppets, ui, levels)
//   - used across kinds                                          -> assets/shared/mixed/
// The name is the texture's key in the extractor's json ("1_v6:85" -> 1_v6_85.png), i.e. library + symbol id of the
// original SWF, the same naming the extractors use for files that are not shared. References in json / scenes /
// scripts are rewritten, the .import file moves along (so the uid stays), unreferenced files go to the Recycle Bin.
// Safe to run again; dedupe.js runs it at its end.
//   node tools/extract/organize_shared.js [--dry]
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');

const GAME = path.join(__dirname, '..', '..', 'game');
const SHARED = path.join(GAME, 'assets', 'shared');
const dry = process.argv.includes('--dry');
const rel = (p) => path.relative(GAME, p).split(path.sep).join('/');
const res = (p) => 'res://' + rel(p);
const MD5 = /^[0-9a-f]{32}\.png$/;

const texts = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (e.name !== '.godot') walk(p); } else if (/\.(json|tscn|tres|gd|cfg)$/.test(e.name)) texts.push(p);
  }
})(GAME);

// which thing a file belongs to: assets/<kind>/<name>/..., scenes/levels/<stage>.tscn -> levels/<stage>; tools/src: nobody
function owner(file) {
  const r = rel(file).split('/');
  if (r[0] === 'assets' && r.length > 3 && ['puppets', 'ui', 'levels'].includes(r[1])) return r[1] + '/' + r[2];
  if (r[0] === 'scenes' && r[1] === 'levels') return 'levels/' + r[2].replace(/\.tscn$/, '');
  return null;
}

// md5 -> { keys:Set, owners:Set, refs:Set(files) }
const info = {};
const at = (h) => info[h] || (info[h] = { keys: new Set(), owners: new Set(), refs: new Set() });
const sharedRe = /res:\/\/assets\/shared\/([0-9a-f]{32})\.png/g;
const keyRe = /"([^"]+)"\s*:\s*\{[^{}]*?"res"\s*:\s*"res:\/\/assets\/shared\/([0-9a-f]{32})\.png"/g;
for (const f of texts) {
  const s = fs.readFileSync(f, 'utf8');
  let m;
  while ((m = sharedRe.exec(s))) {
    const e = at(m[1]);
    e.refs.add(f);
    const o = owner(f);
    if (o) e.owners.add(o);
  }
  while ((m = keyRe.exec(s))) at(m[2]).keys.add(m[1]);
}

// identical content already stored under a readable name (a new extraction re-created a file that is organised)
const named = new Map();
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p); else if (e.name.endsWith('.png') && !MD5.test(e.name)) named.set(crypto.createHash('md5').update(fs.readFileSync(p)).digest('hex'), p);
  }
})(SHARED);

const map = new Map();   // old res -> new res
const moves = [];        // [from, to]
const trash = [];
const taken = new Set();
const files = fs.readdirSync(SHARED).filter((n) => MD5.test(n));
for (const n of files) {
  const h = n.slice(0, -4);
  const from = path.join(SHARED, n);
  const e = info[h];
  if (named.has(h)) { map.set(res(from), res(named.get(h))); trash.push(from); if (fs.existsSync(from + '.import')) trash.push(from + '.import'); continue; }
  if (!e) { trash.push(from); if (fs.existsSync(from + '.import')) trash.push(from + '.import'); continue; }
  const key = [...e.keys].sort()[0];
  const name = (key ? key.replace(/[:\\/]/g, '_') : 'img_' + h.slice(0, 8)) + '.png';
  const owners = [...e.owners];
  let dir;
  if (owners.length === 1 && fs.existsSync(path.join(GAME, 'assets', owners[0]))) dir = path.join(GAME, 'assets', owners[0], 'tex');
  else {
    const kinds = new Set(owners.map((o) => o.split('/')[0]));
    dir = path.join(SHARED, kinds.size === 1 ? [...kinds][0] : 'mixed');
  }
  let to = path.join(dir, name);
  for (let i = 2; taken.has(to) || (fs.existsSync(to) && crypto.createHash('md5').update(fs.readFileSync(to)).digest('hex') !== h); i++) to = path.join(dir, name.replace(/\.png$/, '_' + i + '.png'));
  taken.add(to);
  map.set(res(from), res(to));
  moves.push([from, to]);
}
console.log(`${files.length} md5-named files: ${moves.length} to move, ${trash.filter((t) => t.endsWith('.png')).length} unreferenced / already organised`);
if (dry) { for (const [a, b] of moves.filter(([x]) => 1).slice(0, 25)) console.log(' ', path.basename(a), '->', rel(b)); process.exit(0); }

for (const [a, b] of moves) {
  fs.mkdirSync(path.dirname(b), { recursive: true });
  fs.renameSync(a, b);
  if (fs.existsSync(a + '.import')) fs.renameSync(a + '.import', b + '.import');
}
let changed = 0;
for (const f of texts) {
  const s = fs.readFileSync(f, 'utf8');
  const out = s.replace(sharedRe, (m) => map.get(m) || m);
  if (out !== s) { fs.writeFileSync(f, out); changed++; }
}
// the moved .import files still name the old source: Godot rebuilds them (keeping the uid) on the next import
for (const [, b] of moves) {
  const p = b + '.import';
  if (!fs.existsSync(p)) continue;
  let s = fs.readFileSync(p, 'utf8');
  const out = s.replace(/res:\/\/assets\/shared\/[0-9a-f]{32}\.png/g, res(b));
  if (out !== s) fs.writeFileSync(p, out);
}
console.log('moved', moves.length, 'rewrote', changed, 'files');
if (trash.length) {
  const list = path.join(require('os').tmpdir(), 'organize_trash.txt');
  fs.writeFileSync(list, trash.join('\n'));
  const ps = `Add-Type -AssemblyName Microsoft.VisualBasic; Get-Content -LiteralPath '${list}' -Encoding UTF8 | ForEach-Object { if (Test-Path -LiteralPath $_) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($_, 'OnlyErrorDialogs', 'SendToRecycleBin') } }`;
  cp.execFileSync('powershell', ['-NoProfile', '-Command', ps], { stdio: 'inherit' });
  console.log('moved', trash.length, 'files to the Recycle Bin');
}

// scenes keep a uid next to every texture path: a texture that took the place of an identical one (dedupe) has another uid,
// so refresh the uids of the text scenes / resources from the .import files (after Godot has imported the new files)
if (!dry) {
  const uidOf = (p) => {
    const f = path.join(GAME, p.replace('res://', '') + '.import');
    if (!fs.existsSync(f)) return null;
    const m = /^uid="(uid:\/\/[^"]+)"/m.exec(fs.readFileSync(f, 'utf8'));
    return m ? m[1] : null;
  };
  let fixed = 0;
  for (const f of texts.filter((t) => /\.(tscn|tres)$/.test(t))) {
    const s = fs.readFileSync(f, 'utf8');
    const out = s.replace(/(\[ext_resource [^\]]*?)uid="(uid:\/\/[^"]+)"([^\]]*?path="(res:\/\/[^"]+\.png)")/g, (all, a, uid, b, r) => {
      const want = uidOf(r);
      return want && want !== uid ? a + 'uid="' + want + '"' + b : all;
    });
    if (out !== s) { fs.writeFileSync(f, out); fixed++; }
  }
  if (fixed) console.log('refreshed texture uids in', fixed, 'scenes');
}
