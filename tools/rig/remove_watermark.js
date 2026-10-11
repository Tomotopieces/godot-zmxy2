// Removes the baked-in "4399" stamp from the level artwork. The original scenery carries a faint hand-written
// "4399" engraved on rock bases and brick walls (the portal's watermark). It is found by matching a template of the
// stamp (taken from the stage-1 scenery) against the high-passed brightness of every level texture, at several scales,
// and painted over with the surroundings' own colours.
//
//   node tools/rig/remove_watermark.js            scan every texture of game/assets/levels and shared, report only
//   node tools/rig/remove_watermark.js --fix      ... and paint the stamps out (textures are rewritten in place)
//   node tools/rig/remove_watermark.js --fix <file.png> ...   only these files
'use strict';
const fs = require('fs');
const path = require('path');
const png = require('./png');

const ROOT = path.join(__dirname, '..', '..');
// the stamp as it sits in the stage-1 scenery (a crop of the original picture, kept here because the scenery itself gets cleaned)
const TEMPLATE = { file: 'tools/rig/watermark_template.png', x: 0, y: 0, w: 122, h: 58 };
const SCALES = [0.7, 0.85, 1.0, 1.2, 1.4, 1.7, 2.1];
const COARSE = 4;            // coarse search on a picture shrunk this much
const MIN_COARSE = +(process.env.WM_COARSE || 0.35);
const MIN_FINE = +(process.env.WM_FINE || 0.5);

function luminance(d) {
  const a = new Float32Array(d.width * d.height);
  for (let i = 0; i < a.length; i++) a[i] = d.data[i * 4] * 0.299 + d.data[i * 4 + 1] * 0.587 + d.data[i * 4 + 2] * 0.114;
  return a;
}

function boxBlur(a, w, h, r) {
  const t = new Float32Array(a.length);
  const out = new Float32Array(a.length);
  for (let y = 0; y < h; y++) {
    let s = 0;
    const row = y * w;
    const cnt = (x) => Math.min(x + r, w - 1) - Math.max(x - r, 0) + 1;
    for (let x = 0; x <= Math.min(r, w - 1); x++) s += a[row + x];
    for (let x = 0; x < w; x++) {
      t[row + x] = s / cnt(x);
      if (x + r + 1 < w) s += a[row + x + r + 1];
      if (x - r >= 0) s -= a[row + x - r];
    }
  }
  for (let x = 0; x < w; x++) {
    let s = 0;
    const cnt = (y) => Math.min(y + r, h - 1) - Math.max(y - r, 0) + 1;
    for (let y = 0; y <= Math.min(r, h - 1); y++) s += t[y * w + x];
    for (let y = 0; y < h; y++) {
      out[y * w + x] = s / cnt(y);
      if (y + r + 1 < h) s += t[(y + r + 1) * w + x];
      if (y - r >= 0) s -= t[(y - r) * w + x];
    }
  }
  return out;
}

function shrink(a, w, h, f) {
  const W = Math.floor(w / f), H = Math.floor(h / f);
  const o = new Float32Array(W * H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    let s = 0;
    for (let j = 0; j < f; j++) for (let i = 0; i < f; i++) s += a[(y * f + j) * w + x * f + i];
    o[y * W + x] = s / (f * f);
  }
  return { a: o, w: W, h: H };
}

// brightness minus its local average: the engraving / strokes without the rock's own shading
function highpass(a, w, h, r) {
  const b = boxBlur(a, w, h, r);
  const o = new Float32Array(a.length);
  for (let i = 0; i < a.length; i++) o[i] = a[i] - b[i];
  return o;
}

function templateAt(scale, f) {
  const src = png.decode(path.join(ROOT, TEMPLATE.file));
  const L = luminance(src);
  const patch = new Float32Array(TEMPLATE.w * TEMPLATE.h);
  for (let y = 0; y < TEMPLATE.h; y++) for (let x = 0; x < TEMPLATE.w; x++) patch[y * TEMPLATE.w + x] = L[(TEMPLATE.y + y) * src.width + TEMPLATE.x + x];
  const hp = highpass(patch, TEMPLATE.w, TEMPLATE.h, 9);
  const k = scale / f;
  const tw = Math.max(Math.round(TEMPLATE.w * k), 4), th = Math.max(Math.round(TEMPLATE.h * k), 4);
  const t = new Float32Array(tw * th);
  let mean = 0;
  for (let y = 0; y < th; y++) for (let x = 0; x < tw; x++) {
    // area average of the source pixels this template pixel covers
    const x0 = Math.floor(x / k), x1 = Math.max(Math.floor((x + 1) / k), x0 + 1), y0 = Math.floor(y / k), y1 = Math.max(Math.floor((y + 1) / k), y0 + 1);
    let s = 0, n = 0;
    for (let j = y0; j < Math.min(y1, TEMPLATE.h); j++) for (let i = x0; i < Math.min(x1, TEMPLATE.w); i++) { s += hp[j * TEMPLATE.w + i]; n++; }
    t[y * tw + x] = n ? s / n : 0;
    mean += t[y * tw + x];
  }
  mean /= t.length;
  let norm = 0;
  for (let i = 0; i < t.length; i++) { t[i] -= mean; norm += t[i] * t[i]; }
  return { t, tw, th, norm: Math.sqrt(norm) };
}

// normalised cross-correlation of the template over the picture's high-passed brightness; returns the best peaks
function search(H, w, h, tpl, minScore) {
  const sq = new Float64Array((w + 1) * (h + 1));
  for (let y = 0; y < h; y++) {
    let r = 0;
    for (let x = 0; x < w; x++) { r += H[y * w + x] * H[y * w + x]; sq[(y + 1) * (w + 1) + x + 1] = sq[y * (w + 1) + x + 1] + r; }
  }
  const { t, tw, th, norm } = tpl;
  const peaks = [];
  for (let y = 0; y + th <= h; y++) {
    for (let x = 0; x + tw <= w; x++) {
      const e = sq[(y + th) * (w + 1) + x + tw] - sq[y * (w + 1) + x + tw] - sq[(y + th) * (w + 1) + x] + sq[y * (w + 1) + x];
      if (e < tw * th * 1.0) continue;   // flat area: nothing engraved here
      let num = 0;
      for (let j = 0; j < th; j++) {
        const row = (y + j) * w + x;
        const trow = j * tw;
        for (let i = 0; i < tw; i++) num += t[trow + i] * H[row + i];
      }
      const score = num / (norm * Math.sqrt(e));
      if (score >= minScore) peaks.push({ x, y, tw, th, score });
    }
  }
  return peaks;
}

// stamps the matcher cannot find: half hidden behind other pieces of the same picture, or in the stage-1 floor tile (where
// it is drawn black and bold). [x, y, w, h] in texture pixels, only the visible part.
const MANUAL = {
  '1_v6_86.png': [[3412, 886, 56, 36], [5858, 886, 56, 36]],
  'e2b96b7221852ada4ea8fa907680fcdf.png': [[74, 40, 92, 38]],
};

// textures that repeat sideways (a floor tile): patches may wrap around
const WRAP = { 'e2b96b7221852ada4ea8fa907680fcdf.png': true };

function findStamps(d) {
  const w = d.width, h = d.height;
  const L = luminance(d);
  const sm = shrink(L, w, h, COARSE);
  const Hc = highpass(sm.a, sm.w, sm.h, 5);
  const Hf = highpass(L, w, h, 9);
  const found = [];
  for (const s of SCALES) {
    const coarse = search(Hc, sm.w, sm.h, templateAt(s, COARSE), MIN_COARSE);
    for (const p of coarse) {
      // refine at full resolution around the coarse peak
      const tpl = templateAt(s, 1);
      let best = null;
      for (let dy = -COARSE * 2; dy <= COARSE * 2; dy++) for (let dx = -COARSE * 2; dx <= COARSE * 2; dx++) {
        const x = p.x * COARSE + dx, y = p.y * COARSE + dy;
        if (x < 0 || y < 0 || x + tpl.tw > w || y + tpl.th > h) continue;
        let num = 0, e = 0;
        for (let j = 0; j < tpl.th; j++) for (let i = 0; i < tpl.tw; i++) { const v = Hf[(y + j) * w + x + i]; num += tpl.t[j * tpl.tw + i] * v; e += v * v; }
        const score = e > 0 ? num / (tpl.norm * Math.sqrt(e)) : 0;
        if (!best || score > best.score) best = { x, y, tw: tpl.tw, th: tpl.th, score, scale: s };
      }
      if (best && best.score >= MIN_FINE) found.push(best);
    }
  }
  // keep the best of overlapping detections
  found.sort((a, b) => b.score - a.score);
  const out = [];
  for (const f of found) {
    if (!out.some((o) => Math.abs(o.x - f.x) < Math.max(o.tw, f.tw) * 0.8 && Math.abs(o.y - f.y) < Math.max(o.th, f.th) * 0.8)) out.push(f);
  }
  return out;
}

// Paints a stamp out by copying over it the patch of the same picture whose surroundings look most like this one's
// (the scenery is painterly rock and brick: a nearby patch continues it better than any fill). `others` are the other
// stamps of the picture, never used as a source.
function paintOut(d, st, others, wrapX) {
  const w = d.width, h = d.height;
  const pad = Math.round(st.tw * 0.06) + 3;
  const bx = Math.max(st.x - pad, 0), by = Math.max(st.y - pad, 0);
  const bw = Math.min(st.x + st.tw + pad, w) - bx, bh = Math.min(st.y + st.th + pad, h) - by;
  const RING = 6;
  // the ring around the box: what the copied patch has to match
  const ring = [];
  for (let y = -RING; y < bh + RING; y++) for (let x = -RING; x < bw + RING; x++) {
    if (x >= 0 && y >= 0 && x < bw && y < bh) continue;
    if ((x + y) % 2) continue;
    const X = bx + x, Y = by + y;
    if (X < 0 || Y < 0 || X >= w || Y >= h) continue;
    ring.push([x, y]);
  }
  const hitsStamp = (sx, sy) => [st, ...others].some((o) => [0, -w, w].filter((k) => wrapX || k === 0).some((k) => sx < o.x + k + o.tw + 4 && sx + bw > o.x + k - 4 && sy < o.y + o.th + 4 && sy + bh > o.y - 4));
  const cost = (dx, dy, stop) => {
    let c = 0;
    for (const [x, y] of ring) {
      let SX = bx + dx + x;
      const SY = by + dy + y;
      if (wrapX) SX = ((SX % w) + w) % w;
      if (SX < 0 || SY < 0 || SX >= w || SY >= h) return Infinity;
      const i = ((by + y) * w + bx + x) * 4, j = (SY * w + SX) * 4;
      const da = d.data[i + 3] - d.data[j + 3];
      const dr = d.data[i] - d.data[j], dg = d.data[i + 1] - d.data[j + 1], db = d.data[i + 2] - d.data[j + 2];
      c += dr * dr + dg * dg + db * db + da * da * 2;
      if (c > stop) return Infinity;
    }
    return c;
  };
  let best = { c: Infinity, dx: 0, dy: 0 };
  const RX = wrapX ? w : bw * 4, RY = wrapX ? 6 : bh * 3;
  for (let dy = -RY; dy <= RY; dy += 3) for (let dx = -RX; dx <= RX; dx += 3) {
    if (Math.abs(dx) < bw * 0.6 && Math.abs(dy) < bh * 0.6) continue;
    if (hitsStamp(bx + dx, by + dy)) continue;
    const c = cost(dx, dy, best.c);
    if (c < best.c) best = { c, dx, dy };
  }
  for (let dy = best.dy - 3; dy <= best.dy + 3; dy++) for (let dx = best.dx - 3; dx <= best.dx + 3; dx++) {
    if (hitsStamp(bx + dx, by + dy)) continue;
    const c = cost(dx, dy, best.c);
    if (c < best.c) best = { c, dx, dy };
  }
  if (!isFinite(best.c)) { console.warn('  no patch for', st.x, st.y); return; }
  const FEATHER = 4;
  const src = new Uint8Array(d.data);
  for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) {
    const i = ((by + y) * w + bx + x) * 4;
    const SX = wrapX ? (((bx + best.dx + x) % w) + w) % w : bx + best.dx + x;
    const j = ((by + best.dy + y) * w + SX) * 4;
    const edge = Math.min(x, y, bw - 1 - x, bh - 1 - y);
    const t = Math.min((edge + 1) / FEATHER, 1);
    for (let c = 0; c < 4; c++) d.data[i + c] = Math.round(src[i + c] * (1 - t) + src[j + c] * t);
  }
}

function main() {
  const args = process.argv.slice(2);
  const fix = args.includes('--fix');
  let files = args.filter((a) => !a.startsWith('--'));
  if (!files.length) {
    const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (p.endsWith('.png')) files.push(p); } };
    walk(path.join(ROOT, 'game/assets/levels'));
    walk(path.join(ROOT, 'game/assets/shared'));
  }
  let total = 0;
  for (const f of files) {
    const d = png.decode(f);
    if (d.width < 220 || d.height < 90) continue;
    if (path.basename(f) in MANUAL && !args.includes('--all')) { /* scan it all the same */ }
    const stamps = findStamps(d);
    for (const m of MANUAL[path.basename(f)] || []) stamps.push({ x: m[0], y: m[1], tw: m[2], th: m[3], score: 1, scale: 0 });
    if (!stamps.length) continue;
    total += stamps.length;
    console.log(path.relative(ROOT, f), d.width + 'x' + d.height, stamps.map((s) => `${s.x},${s.y} ${s.tw}x${s.th} s${s.scale} ${s.score.toFixed(2)}`).join(' | '));
    if (fix) {
      for (const s of stamps) paintOut(d, s, stamps.filter((o) => o !== s), path.basename(f) in WRAP);
      png.encode(d, f);
    }
  }
  console.log('stamps', total);
}

if (require.main === module) main();
module.exports = { findStamps, paintOut };
