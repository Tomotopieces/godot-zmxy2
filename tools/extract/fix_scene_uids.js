// Hand-made scenes (game/scenes/levels) keep a uid next to each texture path. When dedupe replaces a texture by an identical shared one,
// the new file gets a new uid once Godot has imported it: run this after the import to bring the scenes' uids up to date.
//   node tools/extract/fix_scene_uids.js [--fix]     (without --fix: only report)
const fs = require('fs'), path = require('path');
const fix = process.argv.includes('--fix');
const GAME = path.join(__dirname, '..', '..', 'game');
let bad = 0, fixed = 0;
const uidOf = (p) => {
  const f = path.join(GAME, p.replace('res://', '') + '.import');
  if (!fs.existsSync(f)) return null;
  const m = /^uid="(uid:\/\/[^"]+)"/m.exec(fs.readFileSync(f, 'utf8'));
  return m ? m[1] : null;
};
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (e.name !== '.godot') walk(p); continue; }
    if (!/\.(tscn|tres)$/.test(e.name)) continue;
    let s = fs.readFileSync(p, 'utf8');
    let changed = false;
    s = s.replace(/(\[ext_resource [^\]]*?)uid="(uid:\/\/[^"]+)"([^\]]*?path="(res:\/\/[^"]+\.png)")/g, (all, a, uid, b, res) => {
      const want = uidOf(res);
      if (want && want !== uid) {
        bad++;
        console.log(path.relative(GAME, p), res, uid, '->', want);
        if (fix) { changed = true; fixed++; return a + 'uid="' + want + '"' + b; }
      }
      return all;
    });
    if (changed) fs.writeFileSync(p, s);
  }
})(GAME);
console.log('mismatched', bad, 'fixed', fixed);
