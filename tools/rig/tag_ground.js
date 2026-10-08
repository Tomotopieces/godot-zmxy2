// Marks which art leaves of a level are the ground tier. The scene's own children (zmxy2_game symbols: floor, rim pieces,
// foreground decoration) sit above the stage mechanisms (doors, boss walls, entrances) in the original's child order,
// the bg<stage><level> artwork from the art library sits below them. Leaf layout: [tex, matrix, colour, ground(0|1)].
//   node tools/rig/tag_ground.js            every game/assets/levels/*/level.json
'use strict';
const fs = require('fs');
const path = require('path');

function tag(d) {
  for (const l of d.art) l[3] = l[0].startsWith('zmxy2_game:') ? 1 : 0;
  return d;
}

if (require.main === module) {
  const root = path.join(__dirname, '..', '..', 'game', 'assets', 'levels');
  for (const lv of fs.readdirSync(root)) {
    const f = path.join(root, lv, 'level.json');
    const d = JSON.parse(fs.readFileSync(f, 'utf8'));
    const g = d.art.filter((l) => l[0].startsWith('zmxy2_game:')).length;
    fs.writeFileSync(f, JSON.stringify(tag(d)));
    console.log(lv, 'art', d.art.length, 'ground', g);
  }
}
module.exports = { tag };
