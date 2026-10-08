// Repairs hairline seams in rasterised vector artwork. A Flash shape made of abutting fills is rasterised with
// anti-aliased edges on both sides of every join, which leaves a 1-2 px line of partial transparency that shows the
// background behind the stage. Flash itself composites such joins seamlessly, so any run of at most MAX_GAP
// not-quite-opaque pixels that is closed by opaque pixels on both sides (along a row or a column) is made opaque.
//   node tools/rig/fix_seams.js                  every shape texture of every level (game/assets/levels)
//   node tools/rig/fix_seams.js <file.png> ...   just these files
// extract_level.js calls fix() after copying a texture.
'use strict';
const fs = require('fs');
const path = require('path');
const png = require('./png');

const MAX_GAP = 6;      // texture pixels (shape textures are rendered at 2x: 3 px of the game)
const OPAQUE = 250;     // alpha counted as solid

function repairLine(d, start, step, n, stats) {
  let i = 0;
  while (i < n) {
    const o = start + i * step * 4;
    if (d[o + 3] >= OPAQUE) { i++; continue; }
    let j = i;
    while (j < n && d[start + j * step * 4 + 3] < OPAQUE && j - i <= MAX_GAP) j++;
    const closed = i > 0 && j < n && d[start + j * step * 4 + 3] >= OPAQUE && j - i <= MAX_GAP;
    if (closed) {
      const a = start + (i - 1) * step * 4, b = start + j * step * 4;
      for (let k = i; k < j; k++) {
        const p = start + k * step * 4, t = (k - i + 1) / (j - i + 1);
        if (d[p + 3] < 128) for (let c = 0; c < 3; c++) d[p + c] = Math.round(d[a + c] * (1 - t) + d[b + c] * t);
        d[p + 3] = 255;
        stats.fixed++;
      }
    }
    i = Math.max(j, i + 1);
  }
}

function fix(file) {
  const img = png.decode(file);
  const { width: w, height: h, data: d } = img, stats = { fixed: 0 };
  for (let y = 0; y < h; y++) repairLine(d, y * w * 4, 1, w, stats);
  for (let x = 0; x < w; x++) repairLine(d, x * 4, w, h, stats);
  if (stats.fixed) png.encode(img, file);
  return stats.fixed;
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
