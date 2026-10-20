// Repairs hairline seams in rasterised vector artwork. A Flash shape made of abutting fills is rasterised with
// anti-aliased edges on both sides of every join, which leaves a 1-2 px line of partial transparency that shows the
// background behind the stage. Flash composites such joins seamlessly.
//
// A seam is told apart from the art's own outline by three things:
//   - it is thin (at most MAX_GAP pixels) and closed by opaque pixels on both sides,
//   - its pixels are mostly covered (alpha >= MIN_ALPHA): two anti-aliased edges that meet cover at least ~75 %,
//     while a real notch or gap in a silhouette is (nearly) empty in the middle,
//   - it is straight: it runs along at least MIN_LINE consecutive rows / columns.
// Only such pixels are made opaque; everything else (silhouette edges, notches) is left alone.
//   node tools/extract/fix_seams.js                  every shape texture of every level (game/assets/levels)
//   node tools/extract/fix_seams.js <file.png> ...   just these files
// extract_level.js calls fix() after copying a texture.
'use strict';
const fs = require('fs');
const path = require('path');
const png = require('./png');

const MAX_GAP = 4;      // texture pixels (shape textures are rendered at 2x: 2 px of the game)
const MIN_ALPHA = 100;  // every pixel of a seam is at least this covered
const OPAQUE = 250;     // alpha counted as solid
const MIN_LINE = 12;    // seams are at least this long

// Marks the pixels of seam-like runs along one line (a row or a column) in `mask`.
function markRuns(d, start, step, n, mask, maskStart, maskStep) {
  let i = 0;
  while (i < n) {
    if (d[start + i * step * 4 + 3] >= OPAQUE) { i++; continue; }
    let j = i;
    let ok = i > 0;
    while (j < n && d[start + j * step * 4 + 3] < OPAQUE && j - i <= MAX_GAP) {
      if (d[start + j * step * 4 + 3] < MIN_ALPHA) ok = false;
      j++;
    }
    if (ok && j < n && j - i <= MAX_GAP && d[start + j * step * 4 + 3] >= OPAQUE) {
      for (let k = i; k < j; k++) mask[maskStart + k * maskStep] = 1;
    }
    i = Math.max(j, i + 1);
  }
}

// Keeps only the marks that form runs of >= MIN_LINE along `along` (1 = across a row, w = down a column).
function straighten(mask, w, h, vertical) {
  const keep = new Uint8Array(mask.length);
  const outer = vertical ? w : h, inner = vertical ? h : w;
  for (let a = 0; a < outer; a++) {
    let b = 0;
    while (b < inner) {
      const idx = (t) => (vertical ? t * w + a : a * w + t);
      if (!mask[idx(b)]) { b++; continue; }
      let e = b;
      while (e < inner && mask[idx(e)]) e++;
      if (e - b >= MIN_LINE) for (let t = b; t < e; t++) keep[idx(t)] = 1;
      b = e;
    }
  }
  return keep;
}

function fix(file) {
  const img = png.decode(file);
  const { width: w, height: h, data: d } = img;
  // a gap found along rows is a vertical seam (it repeats down the rows), and the other way round
  const maskV = new Uint8Array(w * h), maskH = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) markRuns(d, y * w * 4, 1, w, maskV, y * w, 1);
  for (let x = 0; x < w; x++) markRuns(d, x * 4, w, h, maskH, x, w);
  const keepV = straighten(maskV, w, h, true), keepH = straighten(maskH, w, h, false);
  let fixed = 0;
  for (let i = 0; i < w * h; i++) {
    if ((keepV[i] || keepH[i]) && d[i * 4 + 3] < 255) { d[i * 4 + 3] = 255; fixed++; }
  }
  if (fixed) png.encode(img, file);
  return fixed;
}

function main(args) {
  let files = args;
  if (!files.length) {
    const root = path.join(__dirname, '..', '..', 'game', 'assets', 'levels');
    files = [];
    for (const lv of fs.readdirSync(root)) {
      const d = JSON.parse(fs.readFileSync(path.join(root, lv, 'level.json')));
      for (const t of Object.values(d.textures)) {
        if (t.scale === 2 && /\.png$/.test(t.res)) files.push(path.join(__dirname, '..', '..', 'game', t.res.replace('res://', '')));
      }
    }
    files = [...new Set(files)];
  }
  for (const f of files) {
    const n = fix(f);
    if (n) console.log(`${path.relative(process.cwd(), f)}: ${n} px repaired`);
  }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { fix };
