// Splits a level's baked scenery strip into depth layers for parallax. The original paints all of a stage's decoration
// into one wide picture: a soft haze band (a smooth gradient: in every row it is one colour) and, on top of it, objects
// (trees, tombstones, rocks). The objects are told from the haze by differing from the row's dominant colour; touching objects stay together
// as one piece. Pieces taller than TREE_HEIGHT are the big trees (middle layer); the rest stand on the floor with the
// player (no parallax). The haze is the far layer, repainted under the objects with the row's own colour so nothing
// shows through when the layers drift apart.
//
//   node tools/rig/split_layers.js sl11 "1_v6:86" [tree_height]
//
// Rewrites game/assets/levels/<level>/level.json (the strip's leaf becomes the pieces' leaves, and a "parallax" table
// names the layer and scroll scale of the textures that move) and writes the piece pictures next to the strip. The strip
// itself is kept. Run it once on the original level.json.
'use strict';
const fs = require('fs');
const path = require('path');
const png = require('./png');

const ROOT = path.join(__dirname, '..', '..', 'game', 'assets', 'levels');
const HAZE_TOL = 22;      // colour distance (sum of channels) from the row's dominant colour that still counts as haze
const GROW = 3;          // px the objects' mask is grown by (their anti-aliased rim stays with them)
const PAD = 2;
const CORE = 9;          // px the objects are eroded by to find the separate cores (necks thinner than twice this break)
const FAR_SCALE = 0.62;
const TREE_SCALE = 0.86;

const [levelName, texKey, treeHeightArg] = process.argv.slice(2);
if (!levelName || !texKey) { console.error('usage: split_layers.js <level> <texture key> [tree height px]'); process.exit(2); }
const TREE_HEIGHT = +(treeHeightArg || 700);

const file = path.join(ROOT, levelName, 'level.json');
const raw = fs.readFileSync(file, 'utf8');
const d = JSON.parse(raw);
const info = d.textures[texKey];
if (!info) throw new Error('no texture ' + texKey);
const src = png.decode(path.join(__dirname, '..', '..', 'game', info.res.replace('res://', '')));
const W = src.width, H = src.height;
console.log('strip', W + 'x' + H);

// the haze colour of every row: the dominant colour (coarse bins) of the row, averaged; rows without a clear one take the
// nearest row above or below that has
const hazeRow = new Array(H).fill(null);
for (let y = 0; y < H; y++) {
  const bins = new Map();
  for (let x = 0; x < W; x += 2) {
    const p = (y * W + x) * 4;
    if (src.data[p + 3] < 8) continue;
    const k = (src.data[p] >> 3) * 1024 + (src.data[p + 1] >> 3) * 32 + (src.data[p + 2] >> 3);
    bins.set(k, (bins.get(k) || 0) + 1);
  }
  let bk = -1, bv = 0;
  for (const [k, v] of bins) if (v > bv) { bv = v; bk = k; }
  if (bv < W / 2 * 0.08) continue;
  let r = 0, g = 0, bl = 0, n = 0;
  const al = [];
  for (let x = 0; x < W; x += 2) {
    const p = (y * W + x) * 4;
    if (src.data[p + 3] < 8) continue;
    const k = (src.data[p] >> 3) * 1024 + (src.data[p + 1] >> 3) * 32 + (src.data[p + 2] >> 3);
    if (k === bk) { r += src.data[p]; g += src.data[p + 1]; bl += src.data[p + 2]; n++; al.push(src.data[p + 3]); }
  }
  al.sort((u, v) => u - v);
  hazeRow[y] = [r / n, g / n, bl / n, al[al.length >> 1]];
}
const ownRow = hazeRow.map((m) => !!m);
for (let y = 0; y < H; y++) {
  if (hazeRow[y]) continue;
  for (let k = 1; k < 40 && !hazeRow[y]; k++) hazeRow[y] = hazeRow[y - k] || hazeRow[y + k] || null;
}
// a row whose dominant colour was a fluke is outvoted by its neighbours
{
  const sm = hazeRow.map((m) => m);
  const med = (a) => { a.sort((u, v) => u - v); return a[a.length >> 1]; };
  for (let y = 0; y < H; y++) {
    const rows = [];
    for (let k = -8; k <= 8; k++) if (hazeRow[y + k]) rows.push(hazeRow[y + k]);
    if (rows.length >= 5) sm[y] = [0, 1, 2, 3].map((c) => med(rows.map((r) => r[c])));
  }
  for (let y = 0; y < H; y++) hazeRow[y] = sm[y];
}
// objects mask: anything visible that is not the haze colour
let obj = new Uint8Array(W * H);
for (let y = 0; y < H; y++) {
  const m = hazeRow[y];
  for (let x = 0; x < W; x++) {
    const p = (y * W + x) * 4;
    if (src.data[p + 3] < 8) continue;
    if (!m) { obj[y * W + x] = src.data[p + 3] >= 160 ? 1 : 0; continue; }   // above the haze: any picture is an object
    const dd = Math.abs(src.data[p] - m[0]) + Math.abs(src.data[p + 1] - m[1]) + Math.abs(src.data[p + 2] - m[2]);
    obj[y * W + x] = dd > HAZE_TOL && src.data[p + 3] >= 160 ? 1 : 0;   // (the haze fades in thin at its top: not an object)
  }
}
function grow(m, r) {
  const t = new Uint8Array(m.length), o = new Uint8Array(m.length);
  for (let y = 0; y < H; y++) { let last = -1e9; for (let x = 0; x < W; x++) { if (m[y * W + x]) last = x; if (x - last <= r) t[y * W + x] = 1; } last = 1e9; for (let x = W - 1; x >= 0; x--) { if (m[y * W + x]) last = x; if (last - x <= r) t[y * W + x] = 1; } }
  for (let x = 0; x < W; x++) { let last = -1e9; for (let y = 0; y < H; y++) { if (t[y * W + x]) last = y; if (y - last <= r) o[y * W + x] = 1; } last = 1e9; for (let y = H - 1; y >= 0; y--) { if (t[y * W + x]) last = y; if (last - y <= r) o[y * W + x] = 1; } }
  return o;
}
// opening: small specks of opaque pixels inside the haze are not objects
function shrinkMask(m, r) { const inv = new Uint8Array(m.length); for (let i = 0; i < m.length; i++) inv[i] = m[i] ? 0 : 1; const g = grow(inv, r); const o = new Uint8Array(m.length); for (let i = 0; i < m.length; i++) o[i] = g[i] ? 0 : 1; return o; }
obj = grow(shrinkMask(obj, 3), 3);
const objG = grow(obj, GROW);
if (process.env.DEBUG_MASK) {   // the object mask of the first 3400 px, to look at
  const Z = 2, mw = Math.min(W, 3400) / Z, mh = Math.floor(H / Z);
  const o = { width: mw, height: mh, data: new Uint8Array(mw * mh * 4) };
  for (let y = 0; y < mh; y++) for (let x = 0; x < mw; x++) { const v = objG[y * Z * W + x * Z]; const t = (y * mw + x) * 4; o.data[t] = v ? 200 : 255; o.data[t + 1] = v ? 40 : 255; o.data[t + 2] = v ? 40 : 255; o.data[t + 3] = 255; }
  png.encode(o, process.env.DEBUG_MASK);
}

// Pieces: objects that touch are one piece, unless they are joined only by a neck. The mask is eroded until the necks
// break; each remaining core is a seed, and every object pixel joins the nearest seed (flood fill through the mask).
const core = shrinkMask(objG, CORE);
const S = 4, w = Math.ceil(W / S), h = Math.ceil(H / S);
const cm = new Uint8Array(w * h);
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (core[y * W + x]) cm[Math.floor(y / S) * w + Math.floor(x / S)] = 1;
const clab = new Int32Array(w * h);
let nid = 0;
for (let i = 0; i < w * h; i++) {
  if (!cm[i] || clab[i]) continue;
  nid++;
  const st = [i];
  clab[i] = nid;
  while (st.length) {
    const j = st.pop();
    const x = j % w, y = (j - x) / w;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]) {
      const X = x + dx, Y = y + dy;
      if (X < 0 || Y < 0 || X >= w || Y >= h) continue;
      const k = Y * w + X;
      if (cm[k] && !clab[k]) { clab[k] = nid; st.push(k); }
    }
  }
}
const pl = new Int32Array(W * H);   // piece of every pixel
let queue = [];
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const i = y * W + x;
  if (core[i] && objG[i]) { const l = clab[Math.floor(y / S) * w + Math.floor(x / S)]; if (l) { pl[i] = l; queue.push(i); } }
}
for (let head = 0; head < queue.length; head++) {
  const i = queue[head];
  const x = i % W, y = (i - x) / W;
  if (x > 0 && objG[i - 1] && !pl[i - 1]) { pl[i - 1] = pl[i]; queue.push(i - 1); }
  if (x < W - 1 && objG[i + 1] && !pl[i + 1]) { pl[i + 1] = pl[i]; queue.push(i + 1); }
  if (y > 0 && objG[i - W] && !pl[i - W]) { pl[i - W] = pl[i]; queue.push(i - W); }
  if (y < H - 1 && objG[i + W] && !pl[i + W]) { pl[i + W] = pl[i]; queue.push(i + W); }
}
queue = null;
// objects with no core (too thin to survive the erosion) that nothing reached: pieces of their own
for (let i = 0; i < W * H; i++) {
  if (!objG[i] || pl[i]) continue;
  nid++;
  const st = [i];
  pl[i] = nid;
  while (st.length) {
    const j = st.pop();
    const x = j % W, y = (j - x) / W;
    if (x > 0 && objG[j - 1] && !pl[j - 1]) { pl[j - 1] = nid; st.push(j - 1); }
    if (x < W - 1 && objG[j + 1] && !pl[j + 1]) { pl[j + 1] = nid; st.push(j + 1); }
    if (y > 0 && objG[j - W] && !pl[j - W]) { pl[j - W] = nid; st.push(j - W); }
    if (y < H - 1 && objG[j + W] && !pl[j + W]) { pl[j + W] = nid; st.push(j + W); }
  }
}
const boxes = new Map();
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const l = pl[y * W + x];
  if (!l) continue;
  const b = boxes.get(l);
  if (!b) boxes.set(l, { id: l, x0: x, y0: y, x1: x + 1, y1: y + 1, n: 1 });
  else { if (x < b.x0) b.x0 = x; if (x >= b.x1) b.x1 = x + 1; if (y < b.y0) b.y0 = y; if (y >= b.y1) b.y1 = y + 1; b.n++; }
}
const pieces = [...boxes.values()];
const kept = pieces.filter((p) => p.n >= 600);
console.log('pieces', pieces.length, 'kept', kept.length);

// far layer: everything that is not an object; the object areas filled with the row's median haze colour
const far = { width: W, height: H, data: new Uint8Array(W * H * 4) };
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const i = y * W + x, p = i * 4;
    if (!objG[i]) { for (let c = 0; c < 4; c++) far.data[p + c] = src.data[p + c]; continue; }
    const m = hazeRow[y];   // under an object: the row's haze
    if (m && ownRow[y]) { far.data[p] = m[0]; far.data[p + 1] = m[1]; far.data[p + 2] = m[2]; far.data[p + 3] = m[3]; }
  }
}
function crop(img, x0, y0, x1, y1) {
  const cw = x1 - x0, ch = y1 - y0;
  const o = { width: cw, height: ch, data: new Uint8Array(cw * ch * 4) };
  for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) { const s = ((y0 + y) * img.width + x0 + x) * 4, t = (y * cw + x) * 4; for (let c = 0; c < 4; c++) o.data[t + c] = img.data[s + c]; }
  return o;
}
// the far picture's rows that hold anything
let fy0 = H, fy1 = 0;
for (let y = 0; y < H; y++) {
  let n = 0;
  for (let x = 0; x < W; x += 5) if (far.data[(y * W + x) * 4 + 3] > 4) n++;
  if (n > W / 5 * 0.25) { fy0 = Math.min(fy0, y); fy1 = Math.max(fy1, y + 1); }   // (rows with a real stretch of haze)
}
// whatever the far layer holds outside those rows is a few stray rim pixels of the objects: dropped
for (let y = 0; y < H; y++) if (y < fy0 || y >= fy1) far.data.fill(0, y * W * 4, (y + 1) * W * 4);

const dir = path.join(ROOT, levelName, 'tex');
const base = texKey.replace(/[:]/g, '_');
const outLeaves = [];
const newTex = {};
const parallax = d.parallax || {};
const scale = info.scale;
function addPiece(key, img, x0, y0, layer, scrollScale, leaf) {
  const f = path.join(dir, `${base}_${key}.png`);
  png.encode(img, f);
  const k = `${texKey}${key}`;
  newTex[k] = { res: `res://assets/levels/${levelName}/tex/${path.basename(f)}`, ox: info.ox + x0 / scale, oy: info.oy + y0 / scale, scale };
  outLeaves.push([k, leaf[1], leaf[2], leaf[3]]);
  if (scrollScale !== 1) parallax[k] = { layer, scale: scrollScale };
}
const orig = d.art.filter((a) => a[0] === texKey);
if (orig.length !== 1) throw new Error('expected exactly one leaf of ' + texKey + ', found ' + orig.length);
const leaf = orig[0];

addPiece('far', crop(far, 0, fy0, W, fy1), 0, fy0, 'Far', FAR_SCALE, leaf);
let nTree = 0, nProp = 0;
for (const p of kept) {
  const x0 = Math.max(p.x0 - PAD, 0), y0 = Math.max(p.y0 - PAD, 0), x1 = Math.min(p.x1 + PAD, W), y1 = Math.min(p.y1 + PAD, H);
  const img = { width: x1 - x0, height: y1 - y0, data: new Uint8Array((x1 - x0) * (y1 - y0) * 4) };
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    const i = y * W + x;
    if (pl[i] !== p.id) continue;
    const s = i * 4, t = ((y - y0) * img.width + x - x0) * 4;
    for (let c = 0; c < 4; c++) img.data[t + c] = src.data[s + c];
  }
  const tree = p.y1 - p.y0 >= TREE_HEIGHT;
  if (tree) { addPiece('t' + nTree++, img, x0, y0, 'Trees', TREE_SCALE, leaf); } else { addPiece('p' + nProp++, img, x0, y0, 'Props', 1, leaf); }
}
console.log('far rows', fy0, fy1, 'trees', nTree, 'props', nProp);

// the strip's leaf is replaced, in place, by the pieces (far first: it is drawn first)
const at = d.art.indexOf(leaf);
d.art.splice(at, 1, ...outLeaves);
Object.assign(d.textures, newTex);
delete d.textures[texKey];
d.parallax = parallax;
fs.writeFileSync(file, JSON.stringify(d, null, raw.includes('\n ') ? 1 : 0));
console.log('written', path.relative(process.cwd(), file));
