// Scratch helper: apply exact-text replacements listed in a JSON-ish module.
//   node tools/patch.js <patch-module.js>
// The module exports { "<file>": [[old, new], ...] }.
const fs = require('fs');
const path = require('path');
const spec = require(path.resolve(process.argv[2]));
let bad = 0;
for (const file in spec) {
  let s = fs.readFileSync(file, 'utf8');
  for (const [a, b] of spec[file]) {
    const de = t => t.replace(/^	/gm, '');
    if (!s.includes(a) && s.includes(de(a))) { s = s.replace(de(a), () => de(b)); continue; }
    if (!s.includes(a)) { console.error('MISSING in', file, ':', JSON.stringify(a.slice(0, 70))); bad++; continue; }
    s = s.replace(a, () => b);
  }
  if (!bad) fs.writeFileSync(file, s);
}
process.exit(bad ? 1 : 0);
