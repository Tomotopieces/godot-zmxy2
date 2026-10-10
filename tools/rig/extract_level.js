// Extract a stage scene (export.gameSence.sl<stage><level>) into level data for Godot.
//
// Gameplay objects are recognized like the original PhysicsWorld did (by marker child names) and
// exported as plain geometry; all art is flattened to textured sprites (frame 0).
//
// Usage: node extract_level.js <stage> <level> <outDir>
// Output: <outDir>/level.json, <outDir>/tex/*.png
//   { name, fps, size:[w,h], far:{tex,w,h}, art:[[texKey, m, ct]], textures:{},
//     walls:[{kind:'solid'|'oneway', pos:[x,y], size:[w,h], rot}], markers:[{kind, rect}],
//     doors:[{kind, pos, rect, art:[[texKey,m,ct]]}], stops:[{x, y, back}], spawners:[{x,y,stop,enemy,delay,interval,total}] }
'use strict';
const fs = require('fs');
const path = require('path');
const fixSeams = require('./fix_seams');
const { tag } = require('./tag_ground');
const { decompose } = require('./shape_tiles');
const { FlashLib, ROOT, I, mul, rectXf, union, CT_ID, ctMul } = require('./flash_data');

const MARKERS = {
  isWall: 'wall', isThroughWall: 'oneway', isTurnBack: 'turn_back', noContinueGo: 'no_pass', isthron: 'thorn',
  isTransferDoor: 'exit_door', isFb: 'dungeon_door', isBaiguDoor: 'baigu_door', isXingtianDoor: 'xingtian_door',
  isPanguanFire: 'panguan_fire', isHideWall: 'hidden_wall', stophere: 'stop', monsterDisapperaPoint: 'spawner',
};

function main(stage, level, outDir) {
  const game = new FlashLib('zmxy2_game');
  const artLibName = stage === 1 ? '1_v6' : stage === 5 ? '5_v7' : String(stage);
  const art = new FlashLib(artLibName);
  const cls = `export.gameSence.sl${stage}${level}`;
  const sceneId = game.byClass[cls];
  if (sceneId === undefined) throw new Error('no scene ' + cls);
  const out = { name: `sl${stage}${level}`, fps: game.fps, textures: {}, art: [], walls: [], markers: [], doors: [], stops: [], spawners: [] };
  const r2 = (v) => Math.round(v * 100) / 100;

  const texKey = (lib, c) => {
    const k = lib.name + ':' + c;
    if (!(k in out.textures)) out.textures[k] = lib.texture(c);
    return out.textures[k] ? k : null;
  };
  // A shape made of bitmap rectangles (floor tiles, rock faces) becomes those bitmaps again instead of one huge
  // rasterised picture: no seams between abutting pieces, and a run of identical tiles is one repeating strip.
  // A piece: { key, x, y, region: [u, v, w, h, repeat] } (shape-local position; region in bitmap px)
  const imgSize = (lib, id) => {   // pixel size of a bitmap (read from its PNG header)
    const t = lib.J.images[id] && lib.texture(id);
    if (!t) return null;
    const b = fs.readFileSync(t.file);
    return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
  };
  const tilePieces = (lib, c) => {
    const rs = decompose(lib.name, c);
    if (!rs) return null;
    for (const r of rs) if (!imgSize(lib, r.bitmap)) return null;
    rs.forEach((r, i) => { r.order = i; });   // the original paints them in this order
    rs.sort((a, b) => a.bitmap - b.bitmap || a.h - b.h || a.y - b.y || a.x - b.x);
    const runs = [];
    for (const r of rs) {
      const img = imgSize(lib, r.bitmap);
      const last = runs[runs.length - 1];
      const tile = r.su === 1 && r.sv === 1 && r.u === 0 && r.v === 0 && r.w === img.w && r.h === img.h;
      if (tile && last && last.tile && last.bitmap === r.bitmap && Math.abs(last.y - r.y) <= 1 && r.x - (last.x + last.w) >= -8 && r.x - (last.x + last.w) <= 8) {
        last.w = r.x + r.w - last.x; last.n++;
      } else runs.push({ ...r, tile, n: 1 });
    }
    runs.sort((a, b) => a.order - b.order);
    return runs.map((r) => {
      const img = imgSize(lib, r.bitmap);
      if (r.n > 1) return { key: texKey(lib, r.bitmap), x: r.x, y: r.y, sx: 1, sy: 1, region: [0, 0, r.w, r.h, 1] };
      // a single piece (region in bitmap px; a scaled bitmap is drawn scaled): grown by half a stage pixel on every
      // side so neighbours overlap instead of leaving a hairline
      const gu = 0.5 * r.su, gv = 0.5 * r.sv;
      const u0 = Math.max(0, r.u - gu), v0 = Math.max(0, r.v - gv);
      const u1 = Math.min(img.w, r.u + r.w * r.su + gu), v1 = Math.min(img.h, r.v + r.h * r.sv + gv);
      return { key: texKey(lib, r.bitmap), x: r.x + (u0 - r.u) / r.su, y: r.y + (v0 - r.v) / r.sv, sx: 1 / r.su, sy: 1 / r.sv, region: [u0, v0, u1 - u0, v1 - v0, 0] };
    });
  };
  // flatten a character (frame 0) to [texKey, m, ct] leaves
  const flatten = (lib, c, m, ct, acc) => {
    const s = lib.sprite(c);
    if (!s && lib.isShape(c)) {
      const pieces = tilePieces(lib, c);
      if (pieces) { for (const p of pieces) acc.push([p.key, mul(m, [p.sx, 0, 0, p.sy, p.x, p.y]).map((v) => Math.round(v * 10000) / 10000), ct.every((v, i) => v === CT_ID[i]) ? null : ct.map(r2), 0, p.region]); return acc; }
    }
    if (!s) { const k = texKey(lib, c); if (k) acc.push([k, m.map(r2), ct.every((v, i) => v === CT_ID[i]) ? null : ct.map(r2)]); return acc; }
    for (const e of [...(s.frames[0] || [])].sort((a, b) => a.d - b.d)) {
      if (e.clip) continue;
      if (e.name && MARKERS[e.name]) continue;     // marker shapes are invisible gameplay helpers
      if (e.name === 'colipse') continue;
      flatten(lib, e.c, mul(m, e.m), e.ct ? ctMul(ct, e.ct) : ct, acc);
    }
    return acc;
  };
  const boundsOf = (lib, c, depth = 0) => {
    if (lib.J.shapes[c]) return lib.J.shapes[c];
    if (lib.J.images[c]) return { x: 0, y: 0, w: lib.J.images[c].w, h: lib.J.images[c].h };
    const s = lib.sprite(c);
    if (!s || depth > 12) return null;
    let b = null;
    for (const e of s.frames[0] || []) { if (e.clip) continue; const cb = boundsOf(lib, e.c, depth + 1); if (cb) b = union(b, rectXf(e.m, cb)); }
    return b;
  };
  // oriented box of a marker child: center, size, rotation (degrees)
  const obox = (lib, c, m) => {
    const b = boundsOf(lib, c);
    const sx = Math.hypot(m[0], m[1]), sy = Math.hypot(m[2], m[3]);
    const rot = Math.atan2(m[1], m[0]) * 180 / Math.PI;
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    return { pos: [r2(m[0] * cx + m[2] * cy + m[4]), r2(m[1] * cx + m[3] * cy + m[5])], size: [r2(b.w * sx), r2(b.h * sy)], rot: r2(rot) };
  };

  // instance properties set by the Flash component inspector
  const src = fs.readFileSync(path.join(ROOT, 'decomp/res/zmxy2_game/scripts/export/gameSence', `sl${stage}${level}.as`), 'utf8');
  const props = {};
  for (const m of src.matchAll(/this\.(__id\d+_)\.(\w+) = ([^;]+);/g)) {
    if (m[2] === 'componentInspectorSetting') continue;
    let v = m[3].trim();
    try { v = JSON.parse(v); } catch (e) { /* keep string */ }
    (props[m[1]] ||= {})[m[2]] = v;
  }

  const between = stage === 1 ? 1450 : (stage === 4 && level === 1) || (stage === 9 && level === 1) ? 940 : 1150;
  const scene = game.sprite(sceneId);
  let bounds = null;
  for (const e of [...scene.frames[0]].sort((a, b) => a.d - b.d)) {
    const s = game.sprite(e.c);
    const names = s ? (s.frames[0] || []).map((x) => x.name).filter(Boolean) : [];
    const kind = names.map((n) => MARKERS[n]).find(Boolean);
    if (e.name === 'bgContainer') {
      // BaseGameSence puts bg<stage><level> (art library) at y = 65 inside bgContainer
      const bgId = art.byClass[`bg${stage}${level}`];
      if (bgId !== undefined) flatten(art, bgId, mul(e.m, [1, 0, 0, 1, 0, 65]), CT_ID, out.art);
      continue;
    }
    const b = boundsOf(game, e.c);
    if (b) bounds = union(bounds, rectXf(e.m, b));
    if (!kind) { flatten(game, e.c, e.m, e.ct || CT_ID, out.art); continue; }
    const marker = s.frames[0].find((x) => MARKERS[x.name]);
    switch (kind) {
      case 'wall': case 'oneway': case 'hidden_wall': {
        // the marker child is an empty clip: the collision box is the whole object (original used wall.getBounds)
        out.walls.push({ kind: kind === 'oneway' ? 'oneway' : (kind === 'hidden_wall' ? 'hidden' : 'solid'), cls: game.className(e.c), reg: [r2(e.m[4]), r2(e.m[5])], ...obox(game, e.c, e.m) });
        break;
      }
      case 'stop':
        // MainGame overrides the inspector value per stage (stage 1: 1450, 4-1/9-1: 940)
        out.stops.push({ x: r2(e.m[4]), y: r2(e.m[5]), back: between });
        break;
      case 'spawner': {
        const p = props[e.name] || {};
        out.spawners.push({ x: r2(e.m[4]), y: r2(e.m[5]), enemy: p.enemyType | 0, delay: +p.delay || 0, interval: +p.interval || 1, total: p.totalNum | 0 || 1, stop: p.stopPointIdx | 0, random: !!p.isRandom, boss: p.isBoss === true });
        break;
      }
      default: {
        const r = rectXf(e.m, boundsOf(game, e.c));
        const rec = { kind, pos: [r2(e.m[4]), r2(e.m[5])], rect: [r.x, r.y, r.w, r.h].map(r2) };
        if (kind.endsWith('door') || kind === 'panguan_fire') { rec.sym = e.c; out.doors.push(rec); }
        else out.markers.push(rec);
      }
    }
  }
  out.stops.sort((a, b) => a.x - b.x);
  out.size = [r2(bounds.w + bounds.x), r2(bounds.h + bounds.y)];
  out.bounds = [bounds.x, bounds.y, bounds.w, bounds.h].map(r2);
  // far background bitmap floorBg<stage>
  const farId = art.byClass[`floorBg${stage}`];
  if (farId !== undefined) {
    const k = texKey(art, farId);
    out.far = { tex: k };
  }

  // copy textures
  const texDir = path.join(outDir, 'tex');
  fs.mkdirSync(texDir, { recursive: true });
  const resDir = 'res://' + path.relative(path.join(ROOT, 'game'), texDir).split(path.sep).join('/');
  for (const [k, t] of Object.entries(out.textures)) {
    if (!t) { delete out.textures[k]; continue; }
    const fn = k.replace(':', '_') + path.extname(t.file);
    const dst = path.join(texDir, fn);
    // shape textures get their rasterisation seams repaired (the result differs in size from the source,
    // so those are always recopied)
    const repaired = t.scale === 2 && fn.endsWith('.png');
    if (repaired || !fs.existsSync(dst) || fs.statSync(dst).size !== fs.statSync(t.file).size) {
      fs.copyFileSync(t.file, dst);
      if (repaired) fixSeams.fix(dst);
    }
    out.textures[k] = { res: resDir + '/' + fn, ox: t.ox, oy: t.oy, scale: t.scale };
  }
  fs.writeFileSync(path.join(outDir, 'level.json'), JSON.stringify(tag(out), null, 1));
  console.log(out.name, 'size', out.size, 'art', out.art.length, 'walls', out.walls.length, 'markers', out.markers.length, 'doors', out.doors.map((d) => d.kind + '#' + d.sym).join(','), 'stops', out.stops.length, 'spawners', out.spawners.length);
}

if (require.main === module) {
  const [stage, level, outDir] = process.argv.slice(2);
  main(+stage, +level, path.resolve(outDir));
}
module.exports = { main };
