// Flatten a UI symbol (HUD panels, menus) into a node list for Godot.
//
// Each direct child of the symbol (frame 0, depth order) becomes one node:
//   {type:'art',    name, leaves}                         static artwork
//   {type:'frames', name, m, frames:[leaves...], labels}  named multi-frame clip (icons, state indicators)
//   {type:'bar',    name, m, content:leaves, mask0, maskN} clip whose mask slides over the content (gauges)
//   {type:'text',   name, m, ...editTextInfo}             dynamic / static text field
//   {type:'button', name, m, up, over, down, hit}          SimpleButton
// leaves: [[texKey, m, ct]] in node-local space; textures copied to <outDir>/tex.
// A masked group is the leaf ['mask', maskLeaves, contentLeaves] (Flash clipDepth layers).
//
// Usage: node extract_ui.js <lib> <class|#id> <name> <outDir>
'use strict';
const fs = require('fs');
const path = require('path');
const { FlashLib, ROOT, I, mul, rectXf, union, CT_ID, ctMul } = require('./flash_data');

// expose: names of clips nested in a frames node ("instrmc/skill1") that the game drives separately;
// they are left out of the parent's frame art and emitted as nested frames nodes of that frame.
function main(libName, cls, name, outDir, expose = []) {
  const lib = new FlashLib(libName);
  const id = cls.startsWith('#') ? +cls.slice(1) : lib.byClass[cls];
  if (id === undefined) throw new Error('no symbol ' + cls);
  const J = lib.J;
  const out = { name, fps: lib.fps, textures: {}, nodes: [] };
  const r2 = (v) => Math.round(v * 100) / 100;
  const fm = (m) => m.map(r2);
  const fct = (ct) => (ct.every((v, i) => v === CT_ID[i]) ? null : ct.map(r2));

  const texKey = (c) => {
    const k = libName + ':' + c;
    if (!(k in out.textures)) {
      let t = lib.texture(c);
      if (!t && J.texts && J.texts[c]) {
        const f = path.join(ROOT, 'decomp/texts', libName, c + '.svg');
        if (fs.existsSync(f)) t = { file: f, ox: J.texts[c].b.x, oy: J.texts[c].b.y, scale: 1 };
      }
      out.textures[k] = t;
    }
    return out.textures[k] ? k : null;
  };
  const boundsOf = (c, f = 0, depth = 0) => {
    if (J.shapes[c]) return J.shapes[c];
    if (J.images[c]) return { x: 0, y: 0, w: J.images[c].w, h: J.images[c].h };
    if (J.edits && J.edits[c]) return J.edits[c].b;
    const s = J.sprites[c];
    if (!s || depth > 12) return null;
    let b = null;
    for (const e of s.frames[Math.min(f, s.n - 1)] || []) { if (e.clip) continue; const cb = boundsOf(e.c, 0, depth + 1); if (cb) b = union(b, rectXf(e.m, cb)); }
    return b;
  };
  // entries of one frame in depth order, with each mask followed by the layers it clips grouped into it
  const grouped = (entries) => {
    const list = [...entries].sort((a, b) => a.d - b.d), out = [];
    for (let i = 0; i < list.length; i++) {
      const e = list[i];
      if (!e.clip) { out.push(e); continue; }
      const covered = [];
      while (i + 1 < list.length && list[i + 1].d <= e.clip) covered.push(list[++i]);
      out.push({ mask: e, covered });
    }
    return out;
  };
  const flattenMask = (g, m, ct, acc) => {
    const maskLeaves = flatten(g.mask.c, 0, mul(m, g.mask.m), CT_ID, []);
    const content = [];
    for (const x of g.covered) flatten(x.c, 0, mul(m, x.m), x.ct ? ctMul(ct, x.ct) : ct, content);
    if (maskLeaves.length && content.length) acc.push(['mask', maskLeaves, content]);
    return acc;
  };
  // flatten character c at frame f into leaves (nested clips at frame 0)
  const flatten = (c, f, m, ct, acc, name = null) => {
    const s = J.sprites[c];
    if (!s) {
      if (J.buttons && J.buttons[c]) {
        for (const r of J.buttons[c]) if (r[2] & 1) flatten(r[1], 0, mul(m, r.slice(3, 9)), ct, acc);
        return acc;
      }
      if (J.edits && J.edits[c]) { acc.push(['text', fm(m), J.edits[c], name]); return acc; }
      const k = texKey(c);
      if (k) acc.push([k, fm(m), fct(ct)]);
      return acc;
    }
    for (const e of grouped(s.frames[Math.min(f, s.n - 1)] || [])) {
      if (e.mask) flattenMask(e, m, ct, acc);
      else flatten(e.c, 0, mul(m, e.m), e.ct ? ctMul(ct, e.ct) : ct, acc, e.name || null);
    }
    return acc;
  };
  const rectArr = (r) => r && [r.x, r.y, r.w, r.h].map(r2);

  const root = J.sprites[id];
  let pending = null;  // consecutive unnamed static children are merged
  const flushArt = () => { if (pending && pending.leaves.length) out.nodes.push(pending); pending = null; };
  for (const e of grouped(root.frames[0])) {
    if (e.mask) {
      if (!pending) pending = { type: 'art', name: null, m: fm(I), leaves: [] };
      flattenMask(e, I, CT_ID, pending.leaves);
      continue;
    }
    const s = J.sprites[e.c];
    const ct = e.ct || CT_ID;
    if (J.edits && J.edits[e.c]) { flushArt(); out.nodes.push({ type: 'text', name: e.name || null, m: fm(e.m), ...J.edits[e.c] }); continue; }
    if (J.buttons && J.buttons[e.c]) {
      flushArt();
      // a state record may carry its own colour transform (r[9], e.g. the orange hover tint of menu items)
      const st = (bit) => J.buttons[e.c].filter((r) => r[2] & bit).flatMap((r) => flatten(r[1], 0, r.slice(3, 9), r[9] || CT_ID, []));
      let hit = null;
      for (const r of J.buttons[e.c]) if (r[2] & 8) { const b = boundsOf(r[1]); if (b) hit = union(hit, rectXf(r.slice(3, 9), b)); }
      out.nodes.push({ type: 'button', name: e.name || null, m: fm(e.m), up: st(1), over: st(2), down: st(4), hit: rectArr(hit) });
      continue;
    }
    if (s && e.name && (s.n > 1 || s.frames.some((fr) => fr.some((x) => x.clip)))) {
      flushArt();
      const masks = s.frames[0].filter((x) => x.clip);
      const moving = masks.length === 1 && s.n > 1 && s.frames[s.n - 1].some((x) => x.clip && x.d === masks[0].d && (x.m[4] !== masks[0].m[4] || x.m[5] !== masks[0].m[5]));
      if (moving) {
        const mk = masks[0];
        const mN = s.frames[s.n - 1].find((x) => x.clip && x.d === mk.d);
        const content = [];
        for (const x of [...s.frames[0]].sort((a, b) => a.d - b.d)) if (!x.clip && x.d > mk.d && x.d <= mk.clip) flatten(x.c, 0, x.m, x.ct || CT_ID, content);
        const under = [];
        for (const x of [...s.frames[0]].sort((a, b) => a.d - b.d)) if (!x.clip && (x.d < mk.d || x.d > mk.clip)) flatten(x.c, 0, x.m, x.ct || CT_ID, under);
        out.nodes.push({ type: 'bar', name: e.name, m: fm(e.m), frames: s.n, content, other: under,
          mask0: rectArr(rectXf(mk.m, boundsOf(mk.c))), maskN: rectArr(rectXf(mN.m, boundsOf(mN.c))) });
      } else {
        const frames = [];
        const nested = [];
        const exposed = new Set(expose.filter((x) => x.startsWith(e.name + '/')).map((x) => x.slice(e.name.length + 1)));
        for (let f = 0; f < s.n; f++) {
          const acc = [];
          for (const x of grouped(s.frames[f] || [])) {
            if (x.mask) { flattenMask(x, I, CT_ID, acc); continue; }
            const xs = J.sprites[x.c];
            if (x.name && exposed.has(x.name) && xs) {
              const nf = [];
              for (let g = 0; g < xs.n; g++) nf.push(flatten(x.c, g, I, CT_ID, []));
              nested.push({ frame: f, name: x.name, m: fm(x.m), frames: nf, labels: xs.labels });
              continue;
            }
            flatten(x.c, 0, x.m, x.ct || CT_ID, acc, x.name || null);
          }
          frames.push(acc);
        }
        out.nodes.push({ type: 'frames', name: e.name, m: fm(e.m), ct: fct(ct), frames, labels: s.labels, nested });
      }
      continue;
    }
    if (e.name) {
      flushArt();
      out.nodes.push({ type: 'art', name: e.name, m: fm(e.m), leaves: flatten(e.c, 0, I, ct, []) });
      continue;
    }
    if (!pending) pending = { type: 'art', name: null, m: fm(I), leaves: [] };
    flatten(e.c, 0, e.m, ct, pending.leaves);
  }
  flushArt();

  const texDir = path.join(outDir, 'tex');
  fs.mkdirSync(texDir, { recursive: true });
  const resDir = 'res://' + path.relative(path.join(ROOT, 'game'), texDir).split(path.sep).join('/');
  for (const [k, t] of Object.entries(out.textures)) {
    if (!t) { delete out.textures[k]; continue; }
    const fn = k.replace(':', '_') + path.extname(t.file);
    const dst = path.join(texDir, fn);
    if (!fs.existsSync(dst) || fs.statSync(dst).size !== fs.statSync(t.file).size) fs.copyFileSync(t.file, dst);
    out.textures[k] = { res: resDir + '/' + fn, ox: t.ox, oy: t.oy, scale: t.scale };
  }
  fs.writeFileSync(path.join(outDir, 'ui.json'), JSON.stringify(out));
  console.log(name, out.nodes.map((n) => n.type + (n.name ? ':' + n.name : '')).join(' '));
}

if (require.main === module) {
  const [libName, cls, name, outDir, expose] = process.argv.slice(2);
  main(libName, cls, name, path.resolve(outDir), expose ? expose.split(',') : []);
}
module.exports = { main };
