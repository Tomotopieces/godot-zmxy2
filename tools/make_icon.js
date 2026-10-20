// Wukong's head (the HUD portrait) -> game/icon.png (256 px, project/window icon) and build icon.ico (exe icon).
//   node tools/make_icon.js
'use strict';
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const png = require('./extract/png');
const root = path.join(__dirname, '..');
const src = png.decode(path.join(root, 'game', 'assets/ui/role_info/tex/OtherMat_v10_247.png'));   // the HUD portrait
const N = 256, pad = 8, k = (N - 2 * pad) / Math.max(src.width, src.height);
const w = Math.round(src.width * k), h = Math.round(src.height * k);
const ox = Math.floor((N - w) / 2), oy = Math.floor((N - h) / 2);
const out = { width: N, height: N, data: Buffer.alloc(N * N * 4) };
// bilinear, on premultiplied colour so the transparent edge does not darken
for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
  const sx = Math.min((x + 0.5) / k - 0.5, src.width - 1), sy = Math.min((y + 0.5) / k - 0.5, src.height - 1);
  const x0 = Math.max(Math.floor(sx), 0), y0 = Math.max(Math.floor(sy), 0);
  const x1 = Math.min(x0 + 1, src.width - 1), y1 = Math.min(y0 + 1, src.height - 1);
  const fx = sx - x0, fy = sy - y0;
  const acc = [0, 0, 0, 0];
  for (const [px, py, wt] of [[x0, y0, (1 - fx) * (1 - fy)], [x1, y0, fx * (1 - fy)], [x0, y1, (1 - fx) * fy], [x1, y1, fx * fy]]) {
    const i = (py * src.width + px) * 4, a = src.data[i + 3] / 255;
    acc[0] += src.data[i] * a * wt; acc[1] += src.data[i + 1] * a * wt; acc[2] += src.data[i + 2] * a * wt; acc[3] += a * wt;
  }
  const o = ((y + oy) * N + x + ox) * 4;
  if (acc[3] > 0) { out.data[o] = acc[0] / acc[3]; out.data[o + 1] = acc[1] / acc[3]; out.data[o + 2] = acc[2] / acc[3]; }
  out.data[o + 3] = Math.round(acc[3] * 255);
}
png.encode(out, path.join(root, 'game/icon.png'));
// the exe icon holds 16..256 px (Explorer picks its size): built by ImageMagick from the 256 px png
fs.mkdirSync(path.join(root, 'build'), { recursive: true });
cp.execFileSync('magick', [path.join(root, 'game/icon.png'), '-define', 'icon:auto-resize=256,128,64,48,32,16', path.join(root, 'game/icon.ico')]);
console.log('icon', w, h);
