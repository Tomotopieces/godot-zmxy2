// Takes the original's low-grade overlays out of the level data:
//   - the "4399" logo bitmap the original stamps over its scenery as small see-through sprites (watermark),
//   - the grey-blue gradient strip laid along the ground of the first levels as "fog".
// They are art leaves of level.json (by the shared texture file they use). Run after dedupe; safe to run again.
//   node tools/rig/drop_overlays.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..', 'game', 'assets', 'levels');
const DROP = ['12cdbf45acb5abd81d0c603436a952c7.png', 'd6a67103e9c5507714e6c407afcc37ed.png'];
// the same two as texture keys of a freshly extracted level (art library 1_v6: bitmap 30 = the logo, 87 = the ground strip)
const DROP_KEYS = ['1_v6:30', '1_v6:87'];

let total = 0;
for (const lv of fs.readdirSync(ROOT)) {
  const f = path.join(ROOT, lv, 'level.json');
  if (!fs.existsSync(f)) continue;
  const raw = fs.readFileSync(f, 'utf8');
  const d = JSON.parse(raw);
  const before = d.art.length;
  d.art = d.art.filter((a) => !DROP.includes(path.basename(d.textures[a[0]].res)) && !DROP_KEYS.includes(a[0]));
  const used = new Set(d.art.map((a) => a[0]));
  used.add(d.far.tex);
  for (const k of Object.keys(d.textures)) if (!used.has(k) && (DROP.includes(path.basename(d.textures[k].res)) || DROP_KEYS.includes(k))) delete d.textures[k];
  if (d.art.length !== before) {
    fs.writeFileSync(f, JSON.stringify(d, null, raw.includes('\n ') ? 1 : 0));
    console.log(lv, 'dropped', before - d.art.length);
    total += before - d.art.length;
  }
}
console.log('dropped', total);
