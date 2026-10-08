// Copy equipment icons (<id>) and ground sprites (fall_<id>) into game/assets/items/.
//   node tools/rig/extract_icons.js
const fs = require('fs');
const path = require('path');
const { FlashLib } = require('./flash_data');

const ROOT = path.join(__dirname, '..', '..');
const OUT = path.join(ROOT, 'game/assets/items');
const LIBS = ['OtherMat_v10', 'Common_v7', 'backpack_v5', 'zmxy2_game', 'Common_v6'];
const items = require(path.join(ROOT, 'tools/data/equipment.json')).items;

const libs = LIBS.map((n) => { try { return new FlashLib(n); } catch (e) { return null; } }).filter(Boolean);
fs.mkdirSync(OUT, { recursive: true });

// image class -> png (bitmap classes, or a sprite whose first frame is a single image/shape)
function find(cls) {
  for (const L of libs) {
    const id = L.byClass[cls];
    if (id === undefined) continue;
    let t = L.texture(id);
    if (!t) {
      const sp = L.sprite(id);
      const leaf = sp && sp.frames[0] && sp.frames[0].length === 1 ? sp.frames[0][0] : null;
      if (leaf) t = L.texture(leaf.c);
    }
    if (t) return t;
  }
  return null;
}

let n = 0;
const missing = [];
for (const id of Object.keys(items)) {
  for (const [cls, file] of [[id, `${id}.png`], ['fall_' + id, `fall_${id}.png`]]) {
    const t = find(cls);
    if (!t) { missing.push(cls); continue; }
    fs.copyFileSync(t.file, path.join(OUT, file));
    n++;
  }
}
console.log('icons', n, 'missing', missing.length, missing.join(' '));
