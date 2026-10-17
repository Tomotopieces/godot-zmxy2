// Takes the original's low-grade overlays out of the level data:
//   - the "4399" logo bitmap the original stamps over its scenery as small see-through sprites (watermark),
//   - the grey-blue gradient strip laid along the ground of the first levels as "fog".
// They are art leaves of level.json, found by their texture key. Safe to run again.
//   node tools/rig/drop_overlays.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..', 'game', 'assets', 'levels');
// texture keys per level (the art library's symbol ids differ from level to level): the logo bitmap and the strips
const DROP = { sl11: ['1_v6:30', '1_v6:87'], sl12: ['1_v6:30', '1_v6:60'], sl13: ['1_v6:30', '1_v6:2'],
  sl21: ['2:597', '2:608'], sl23: ['2:597'], sl31: ['3:1036', '3:1102'], sl32: ['3:1036'], sl33: ['3:1036', '3:1054'], sl41: ['4:306', '4:307'] };

let total = 0;
for (const lv of fs.readdirSync(ROOT)) {
  const f = path.join(ROOT, lv, 'level.json');
  if (!fs.existsSync(f)) continue;
  const raw = fs.readFileSync(f, 'utf8');
  const d = JSON.parse(raw);
  const DROP_KEYS = DROP[lv] || [];
  const before = d.art.length;
  d.art = d.art.filter((a) => !DROP_KEYS.includes(a[0]));
  const used = new Set(d.art.map((a) => a[0]));
  used.add(d.far.tex);
  for (const k of Object.keys(d.textures)) if (!used.has(k) && DROP_KEYS.includes(k)) delete d.textures[k];
  if (d.art.length !== before) {
    fs.writeFileSync(f, JSON.stringify(d, null, raw.includes('\n ') ? 1 : 0));
    console.log(lv, 'dropped', before - d.art.length);
    total += before - d.art.length;
  }
}
console.log('dropped', total);
