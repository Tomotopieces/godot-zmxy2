// Gives a level's baked scenery strip a distant layer for parallax. The original paints all of a stage's decoration into
// one wide picture: a soft haze band (a smooth gradient: in every row it is one colour) with the objects (trees,
// tombstones, a gate) painted over it, overlapping each other densely. Cutting the objects apart would tear decorations
// in two, so they stay together as the ground layer. What is separated is the haze:
//   - "far": the haze band alone (the objects' places repainted with the row's own haze colour), with silhouettes of
//     distant ruins and trees standing in it - cut-outs of the objects themselves, flattened to the haze colour, smaller
//     and repeated. It drifts slower than the ground and is slightly out of focus: that is the depth.
//   - "ground": the objects (and their rim, which already carries the haze it was blended with).
//
//   node tools/rig/split_layers.js sl11 "1_v6:86"
//
// Rewrites game/assets/levels/<level>/level.json (the strip's leaf becomes the two leaves, and a "parallax" table names
// the layer and scroll scale of the texture that drifts) and writes the two pictures next to the strip, which is kept.
// Run it once on the original level.json.
'use strict';
const fs = require('fs');
const path = require('path');
const png = require('./png');

const ROOT = path.join(__dirname, '..', '..', 'game', 'assets', 'levels');
const STRONG = 60;        // colour distance at which a pixel is certainly part of an object
const HAZE_TOL = 22;      // colour distance (sum of channels) from the row's dominant colour that still counts as haze
const GROW = 3;           // px the objects' mask is grown by (their anti-aliased rim stays with them)
const FAR_SCALE = 0.55;
const SIL_SCALE = [0.5, 0.62, 0.45, 0.58];   // sizes of the distant silhouettes
const SIL_ALPHA = 0.42;
const SIL_DARKEN = 0.84;  // the haze colour times this: a shade darker than the air
// x ranges of the strip (texture px) cut out as silhouettes: clusters of tombstones and dead trees, the broken house, the trees
const SIL_RANGES = [[0, 520], [1000, 1700], [1860, 2400], [2640, 3300], [3300, 4100], [4700, 5300], [5800, 6600]];

const [levelName, texKey] = process.argv.slice(2);
if (!levelName || !texKey) { console.error('usage: split_layers.js <level> <texture key>'); process.exit(2); }

const file = path.join(ROOT, levelName, 'level.json');
const raw = fs.readFileSync(file, 'utf8');
const d = JSON.parse(raw);
const info = d.textures[texKey];
if (!info) throw new Error('no texture ' + texKey);
const src = png.decode(path.join(__dirname, '..', '..', 'game', info.res.replace('res://', '')));
const W = src.width, H = src.height;
console.log('strip', W + 'x' + H);

// --- the haze colour of every row: the dominant colour of the row (coarse bins), cleaned up by its neighbours ---
let hazeRow = new Array(H).fill(null);
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
  let r = 0, g = 0, b = 0, n = 0;
  const al = [];
  for (let x = 0; x < W; x += 2) {
    const p = (y * W + x) * 4;
    if (src.data[p + 3] < 8) continue;
    const k = (src.data[p] >> 3) * 1024 + (src.data[p + 1] >> 3) * 32 + (src.data[p + 2] >> 3);
    if (k === bk) { r += src.data[p]; g += src.data[p + 1]; b += src.data[p + 2]; n++; al.push(src.data[p + 3]); }
  }
  al.sort((u, v) => u - v);
  hazeRow[y] = [r / n, g / n, b / n, al[al.length >> 1]];
}
const ownRow = hazeRow.map((m) => !!m);
{
  const sm = hazeRow.map((m) => m);
  const med = (a) => { a.sort((u, v) => u - v); return a[a.length >> 1]; };
  for (let y = 0; y < H; y++) {
    const rows = [];
    for (let k = -8; k <= 8; k++) if (hazeRow[y + k]) rows.push(hazeRow[y + k]);
    if (rows.length >= 5) sm[y] = [0, 1, 2, 3].map((c) => med(rows.map((r) => r[c])));
  }
  hazeRow = sm;
}
for (let y = 0; y < H; y++) {
  if (hazeRow[y]) continue;
  for (let k = 1; k < 40 && !hazeRow[y]; k++) hazeRow[y] = hazeRow[y - k] || hazeRow[y + k] || null;
}
let haze0 = H, haze1 = 0;
for (let y = 0; y < H; y++) if (ownRow[y]) { haze0 = Math.min(haze0, y); haze1 = Math.max(haze1, y + 1); }

// --- the objects: anything visible that is not the haze colour (an object that fades into the haze at its foot is
// still one: colour, not opacity) ---
function grow(m, r) {
  const t = new Uint8Array(m.length), o = new Uint8Array(m.length);
  for (let y = 0; y < H; y++) { let last = -1e9; for (let x = 0; x < W; x++) { if (m[y * W + x]) last = x; if (x - last <= r) t[y * W + x] = 1; } last = 1e9; for (let x = W - 1; x >= 0; x--) { if (m[y * W + x]) last = x; if (last - x <= r) t[y * W + x] = 1; } }
  for (let x = 0; x < W; x++) { let last = -1e9; for (let y = 0; y < H; y++) { if (t[y * W + x]) last = y; if (y - last <= r) o[y * W + x] = 1; } last = 1e9; for (let y = H - 1; y >= 0; y--) { if (t[y * W + x]) last = y; if (last - y <= r) o[y * W + x] = 1; } }
  return o;
}
const obj = new Uint8Array(W * H);
const faint = new Uint8Array(W * H);
const strong = new Uint8Array(W * H);   // clearly not haze: a real object's pixel
for (let y = 0; y < H; y++) {
  const m = hazeRow[y];
  for (let x = 0; x < W; x++) {
    const p = (y * W + x) * 4;
    if (src.data[p + 3] < 24) continue;
    if (!ownRow[y]) { obj[y * W + x] = 1; continue; }   // outside the haze band: any picture is an object
    const dd = Math.abs(src.data[p] - m[0]) + Math.abs(src.data[p + 1] - m[1]) + Math.abs(src.data[p + 2] - m[2]);
    obj[y * W + x] = dd > HAZE_TOL && src.data[p + 3] >= 40 ? 1 : 0;
    strong[y * W + x] = dd > STRONG && src.data[p + 3] >= 120 ? 1 : 0;
  }
}
// faint things (the far buildings and fences the artist painted into the haze) are pieces with no strong pixel at all:
// they belong to the far layer, with the haze
{
  const seen = new Uint8Array(W * H);
  const stack = [];
  for (let i0 = 0; i0 < W * H; i0++) {
    if (!obj[i0] || seen[i0]) continue;
    const members = [];
    let hasStrong = false;
    stack.push(i0);
    seen[i0] = 1;
    while (stack.length) {
      const j = stack.pop();
      members.push(j);
      if (strong[j]) hasStrong = true;
      const x = j % W, y = (j - x) / W;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        if (!dx && !dy) continue;
        const X = x + dx, Y = y + dy;
        if (X < 0 || Y < 0 || X >= W || Y >= H) continue;
        const k = Y * W + X;
        if (obj[k] && !seen[k]) { seen[k] = 1; stack.push(k); }
      }
    }
    if (!hasStrong) for (const j of members) { obj[j] = 0; faint[j] = 1; }
  }
}
// hairlines: where the haze colour of a row is a shade off, a one-pixel row of "object" runs along the band. No object is a
// long thin horizontal line: such runs are haze after all (and are repainted in the far layer).
const junk = new Uint8Array(W * H);
for (let y = 4; y < H - 4; y++) {
  let x = 0;
  while (x < W) {
    if (!obj[y * W + x]) { x++; continue; }
    let e = x;
    while (e < W && obj[y * W + e]) e++;
    if (e - x >= 60) {
      let thin = 0;
      for (let k = x; k < e; k++) if (!obj[(y - 4) * W + k] && !obj[(y + 4) * W + k]) thin++;
      if (thin >= (e - x) * 0.85) for (let k = x; k < e; k++) junk[y * W + k] = 1;
    }
    x = e;
  }
}
for (let i = 0; i < W * H; i++) if (junk[i]) obj[i] = 0;
const objG = grow(obj, GROW);
for (let i = 0; i < W * H; i++) if (junk[i]) objG[i] = 1;   // (the far layer repaints them; the ground layer keeps them out)

// --- the ground layer: the strip's objects ---
const ground = { width: W, height: H, data: new Uint8Array(W * H * 4) };
for (let i = 0; i < W * H; i++) if (objG[i] && !junk[i]) for (let c = 0; c < 4; c++) ground.data[i * 4 + c] = src.data[i * 4 + c];

// --- the far layer: haze (the objects' places repainted with the row's haze) + distant silhouettes ---
const hazeImg = { width: W, height: H, data: new Uint8Array(W * H * 4) };
for (let y = 0; y < H; y++) {
  const m = hazeRow[y];
  for (let x = 0; x < W; x++) {
    const i = y * W + x, p = i * 4;
    if (!objG[i] && src.data[p + 3] >= 8) { for (let c = 0; c < 4; c++) hazeImg.data[p + c] = src.data[p + c]; continue; }
    // under an object, and in the odd transparent row or speck the strip has inside its band: the row's own haze
    if (y >= haze0 && y < haze1) { hazeImg.data[p] = m[0]; hazeImg.data[p + 1] = m[1]; hazeImg.data[p + 2] = m[2]; hazeImg.data[p + 3] = m[3]; }
  }
}
const baseY = haze1 - 4;   // the silhouettes stand on the band's lower edge
const sil = SIL_RANGES.map(([x0, x1]) => {
  let ty = H;
  for (let y = 0; y < baseY; y++) { let any = false; for (let x = x0; x < Math.min(x1, W); x += 2) if (obj[y * W + x]) { any = true; break; } if (any) { ty = y; break; } }
  return { x0, x1: Math.min(x1, W), ty };
}).filter((s) => s.ty < baseY - 40);
const placed = [];
for (let cx = 250, k = 0; cx < W - 400; k++) {
  const s = sil[(k * 5 + 2) % sil.length];
  const sc = SIL_SCALE[k % SIL_SCALE.length];
  placed.push({ x: cx, s, sc, flip: k % 2 === 1, w: Math.round((s.x1 - s.x0) * sc), h: Math.round((baseY - s.ty) * sc) });
  cx += Math.round((s.x1 - s.x0) * sc * (1.4 + 0.3 * (k % 3)));
}
const top = Math.max(Math.min(haze0, baseY - Math.max(...placed.map((p) => p.h)) - 4), 0);
const FH = haze1 - top;
const far = { width: W, height: FH, data: new Uint8Array(W * FH * 4) };
for (let y = Math.max(haze0, top); y < haze1; y++) for (let x = 0; x < W; x++) { const s = (y * W + x) * 4, t = ((y - top) * W + x) * 4; for (let c = 0; c < 4; c++) far.data[t + c] = hazeImg.data[s + c]; }
const tint = hazeRow[baseY];
const col = [tint[0] * SIL_DARKEN, tint[1] * SIL_DARKEN, tint[2] * SIL_DARKEN];
for (const p of placed) {
  for (let oy = 0; oy < p.h; oy++) for (let ox = 0; ox < p.w; ox++) {
    const sx = p.s.x0 + Math.floor((p.flip ? p.w - 1 - ox : ox) / p.sc);
    const sy = baseY - Math.floor((p.h - 1 - oy) / p.sc);
    if (sx < 0 || sx >= W || sy < 0 || sy >= H || !obj[sy * W + sx]) continue;
    const X = p.x + ox, Y = baseY - (p.h - 1 - oy) - top;
    if (X < 0 || X >= W || Y < 0 || Y >= FH) continue;
    const t = (Y * W + X) * 4;
    // the cut-out's sides fade out: its edges are an x range of the picture, not an object's outline
    const edge = Math.min(1, ox / (p.w * 0.18), (p.w - 1 - ox) / (p.w * 0.18));
    const a = SIL_ALPHA * Math.max(edge, 0), ha = far.data[t + 3] / 255;
    const oa = a + ha * (1 - a);
    for (let c = 0; c < 3; c++) far.data[t + c] = Math.round((col[c] * a + far.data[t + c] * ha * (1 - a)) / oa);
    far.data[t + 3] = Math.round(oa * 255);
  }
}
console.log('far', W + 'x' + FH, 'silhouettes', placed.length);

// --- write ---
function crop(img, y0, y1) {
  const o = { width: img.width, height: y1 - y0, data: new Uint8Array(img.width * (y1 - y0) * 4) };
  o.data.set(img.data.subarray(y0 * img.width * 4, y1 * img.width * 4));
  return o;
}
let gy0 = H, gy1 = 0;
for (let y = 0; y < H; y++) for (let x = 0; x < W; x += 3) if (ground.data[(y * W + x) * 4 + 3] > 0) { gy0 = Math.min(gy0, y); gy1 = Math.max(gy1, y + 1); break; }
const dir = path.join(ROOT, levelName, 'tex');
const base = texKey.replace(/[:]/g, '_');
const scale = info.scale;
const orig = d.art.filter((a) => a[0] === texKey);
if (orig.length !== 1) throw new Error('expected exactly one leaf of ' + texKey + ', found ' + orig.length);
const leaf = orig[0];
const newTex = {};
const outLeaves = [];
const parallax = d.parallax || {};
function add(key, img, y0, layer, scrollScale) {
  const f = path.join(dir, `${base}_${key}.png`);
  png.encode(img, f);
  const k = `${texKey}${key}`;
  newTex[k] = { res: `res://assets/levels/${levelName}/tex/${path.basename(f)}`, ox: info.ox, oy: info.oy + y0 / scale, scale };
  outLeaves.push([k, leaf[1], leaf[2], leaf[3]]);
  if (scrollScale !== 1) parallax[k] = { layer, scale: scrollScale };
}
add('far', far, top, 'Far', FAR_SCALE);
add('ground', crop(ground, gy0, gy1), gy0, 'Ground', 1);
const at = d.art.indexOf(leaf);
d.art.splice(at, 1, ...outLeaves);
Object.assign(d.textures, newTex);
delete d.textures[texKey];
d.parallax = parallax;
fs.writeFileSync(file, JSON.stringify(d, null, raw.includes('\n ') ? 1 : 0));
console.log('written', path.relative(process.cwd(), file));
