// Replaces lettering that the original draws as bitmaps with real text (so it uses the game font).
// tools/data/ui_text.json lists, per UI and texture key, what to do:
//   { "<ui>": { "<lib>:<char id>": { "text": "继续游戏", "color": "#ffffff", "outline": "#000000", "outline_size": 3,
//                                    "erase": [x, y, w, h], "mode": "clear" | "fill", "box": [x, y, w, h],
//                                    "align": "center" | "left" | "right", "size": 16, "bold": true } } }
//   - erase: pixels of the texture holding the lettering (texture px). Omitted = the whole texture is lettering.
//   - mode: "clear" makes the pixels transparent (lettering over nothing); "fill" paints over them with the colours
//     on the left / right of the rectangle (lettering over a flat panel).
//   - box: where the label goes (texture px; default = the erased rectangle). The font size fits the box unless "size".
// The texture copy in game/assets/ui/<ui>/tex is rebuilt from the pristine export every run and
// game/assets/ui/<ui>/ui.json gets a "label" entry on that texture (read by UiLayout).
//   node tools/rig/ui_text.js [ui ...]
'use strict';
const fs = require('fs');
const path = require('path');
const png = require('./png');
const { FlashLib, ROOT } = require('./flash_data');

const SPEC = path.join(ROOT, 'tools/data/ui_text.json');

function erase(img, r, mode) {
  const [x0, y0, w, h] = r, W = img.width, d = img.data;
  const at = (x, y) => (Math.min(Math.max(y, 0), img.height - 1) * W + Math.min(Math.max(x, 0), W - 1)) * 4;
  for (let y = y0; y < Math.min(y0 + h, img.height); y++) {
    const a = at(x0 - 1, y), b = at(x0 + w, y);
    for (let x = x0; x < Math.min(x0 + w, W); x++) {
      const p = at(x, y);
      if (mode === 'fill' && (d[a + 3] > 0 || d[b + 3] > 0)) {
        const t = (x - x0 + 0.5) / w;
        for (let c = 0; c < 4; c++) d[p + c] = Math.round(d[a + c] * (1 - t) + d[b + c] * t);
      } else { d[p] = d[p + 1] = d[p + 2] = d[p + 3] = 0; }
    }
  }
}

function main(only) {
  const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8'));
  const libs = {};
  for (const ui of Object.keys(spec)) {
    if (ui.startsWith('_') || (only.length && !only.includes(ui))) continue;
    const dir = path.join(ROOT, 'game/assets/ui', ui);
    const jf = path.join(dir, 'ui.json');
    const d = JSON.parse(fs.readFileSync(jf, 'utf8'));
    for (const [key, s] of Object.entries(spec[ui])) {
      const info = d.textures[key];
      if (!info) { console.error(`${ui}: no texture ${key}`); continue; }
      const [lib, id] = key.split(':');
      const src = (libs[lib] = libs[lib] || new FlashLib(lib)).texture(id).file;
      const dst = path.join(ROOT, 'game', info.res.replace('res://', ''));
      const img = png.decode(src);
      const rect = s.erase || [0, 0, img.width, img.height];
      erase(img, rect, s.mode || (s.erase ? 'fill' : 'clear'));
      png.encode(img, dst);
      const { text, color, outline, outline_size, align, size, bold } = s;
      info.label = { text, color: color || '#ffffff', outline: outline || '#000000', outline_size: outline_size ?? 3,
        align: align || 'center', box: s.box || rect, size: size || 0, bold: bold !== false };
    }
    fs.writeFileSync(jf, JSON.stringify(d));
    console.log(ui, Object.keys(spec[ui]).length, 'labels');
  }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { main };
