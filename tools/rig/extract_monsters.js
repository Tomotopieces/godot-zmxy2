// Extract monster numbers from every export/monster/MonsterNN.as constructor into tools/data/monsters_auto.json.
// The AS3 constructor is turned into JS and evaluated once per scene the monster appears in (constructors
// branch on gc.curStage / gc.curLevel, e.g. a regular monster becomes the stage boss), plus once for its home lib.
//   node tools/rig/extract_monsters.js
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const RES = path.join(ROOT, 'decomp/res');
const OUT = path.join(ROOT, 'tools/data/monsters_auto.json');
const SCENES = path.join(RES, 'zmxy2_game/scripts/export/gameSence');

const stageLib = (stage) => (stage === 1 ? '1_v6' : stage === 5 ? '5_v7' : String(stage));
const SHARED_LIBS = ['Common_v7', 'Common_v6', 'zmxy2_game'];
const { FlashLib } = require('./flash_data');

// lib whose SWF holds the monster's art symbol (its code is duplicated into many SWFs)
const ART_LIB = {};
for (const ln of fs.readdirSync(RES)) {
  let L;
  try { L = new FlashLib(ln); } catch (e) { continue; }
  for (const [c, sid] of Object.entries(L.byClass)) {
    const m = c.match(/^export\.monster\.Monster(\d+)$/);
    if (m && L.sprite(sid) && !ART_LIB[m[1]]) ART_LIB[m[1]] = ln;
  }
}
const libStage = (lib) => (lib === '1_v6' ? 1 : lib === '5_v7' ? 5 : /^\d+$/.test(lib) ? +lib : 1);

// scene name slXY -> [stage, level]; sl101..sl106 = stage 10, sl111 = stage 11
function sceneId(name) {
  const n = name.slice(2);
  if (n.length === 2) return [+n[0], +n[1]];
  return [+n.slice(0, 2), +n.slice(2)];
}

// spawners per scene: enemyType, totalNum, isBoss (set on the spawned monster by the scene)
function sceneSpawns() {
  const out = {};
  for (const f of fs.readdirSync(SCENES)) {
    if (!/^sl\d+\.as$/.test(f)) continue;
    const src = fs.readFileSync(path.join(SCENES, f), 'utf8');
    const props = {};
    for (const m of src.matchAll(/this\.(__id\d+_)\.(\w+) = ([^;]+);/g)) (props[m[1]] ||= {})[m[2]] = m[3].trim();
    const spawns = Object.values(props).filter((p) => p.enemyType).map((p) => ({ enemy: +p.enemyType, total: +(p.totalNum || 1) }));
    const bosses = Object.values(props).filter((p) => p.isBoss === 'true').length;
    out[f.slice(0, -3)] = { spawns, bossFlags: bosses };
  }
  return out;
}

function findClass(id, stage) {
  const libs = [stageLib(stage), ART_LIB[id], ...SHARED_LIBS, ...fs.readdirSync(RES)].filter(Boolean);
  for (const lib of libs) {
    const f = path.join(RES, lib, 'scripts/export/monster', `Monster${id}.as`);
    if (fs.existsSync(f)) return { lib, file: f };
  }
  return null;
}

// AS3 constructor body -> JS function(o, gc, Math)
function ctorToJs(src, id) {
  const m = src.match(new RegExp(`public function Monster${id}\\(\\)\\s*\\{([\\s\\S]*?)\\n      \\}`));
  if (!m) return null;
  return m[1]
    .replace(/super\(\);/g, '')
    .replace(/var (\w+):[\w.*<>]+/g, 'var $1')
    .replace(/\s+as\s+[\w.]+/g, '')
    .replace(/function\s*\(([^)]*)\)\s*:\s*[\w*]+/g, (_, a) => 'function(' + a.replace(/:\s*[\w.*]+/g, '') + ')')
    .replace(/\bthis\./g, 'o.')
    .replace(/\bthis\b/g, 'o')
    .replace(/new (\w+)\(/g, 'NEW("$1",');
}

// Universal stub: any property / call / construction yields another stub (engine APIs the numbers don't need).
const STUB = new Proxy(function () {}, {
  get: (t, k) => (k === Symbol.toPrimitive ? () => 0 : STUB),
  apply: () => STUB,
  construct: () => STUB,
});

function evaluate(body, ctx) {
  const target = { protectedParamsObject: {}, attackBackInfoDict: {}, fallList: [], magicBulletArray: [] };
  const o = new Proxy(target, {
    get: (t, k) => (k in t ? t[k] : STUB),
    set: (t, k, v) => { t[k] = v; return true; },
  });
  const gc = new Proxy({ curStage: ctx.stage, curLevel: ctx.level, gameMode: 1, playNum: 1 }, { get: (t, k) => (k in t ? t[k] : STUB) });
  const M = Object.create(Math); M.random = () => 0.5;
  // capitalised identifiers are AS3 classes / singletons -> stubs
  // (plus the display-list methods the decompiler leaves unqualified)
  const BARE = new Set(['addFrameScript', 'addEventListener', 'removeEventListener', 'gotoAndStop', 'gotoAndPlay', 'stop', 'play', 'setTimeout', 'setInterval']);
  const globals = new Proxy({}, {
    has: (t, k) => typeof k === 'string' && ((/^[A-Z]/.test(k) && k !== 'Math') || BARE.has(k)),
    get: (t, k) => (k === Symbol.unscopables ? undefined : STUB),
  });
  try {
    Function('o', 'gc', 'Math', 'NEW', 'G', 'trace', 'with (G) {' + body + '\n}')(o, gc, M, () => STUB, globals, () => {});
  } catch (e) {
    return { error: e.message };
  }
  return { ok: target };
}

function summarize(res) {
  if (res.error) return res;
  const o = res.ok;
  const p = o.protectedParamsObject;
  const attacks = {};
  for (const [k, a] of Object.entries(o.attackBackInfoDict || {})) {
    attacks[k] = { power: a.power, kind: a.attackKind, knockback: a.attackBackSpeed, interval: a.attackInterval, max_hits: a.hitMaxCount };
    if (a.addEffect) attacks[k].add_effect = a.addEffect;
  }
  const r = {
    name: o.monsterName || '', speed: o.horizenSpeed, hp: p.Hp, sight: p.mysee, attack_chance: p.isattback,
    range: o.attackRange, def: p.def || 0, mdef: p.mDef || 0, exp: p.exp || 0, rage: p.gxp || 0,
    equip_chance: p.probability, stone_rate: p.stoneFallRate, boss: !!o.isBoss, fly: !!o.isFly,
    equip_drops: (o.fallList || []).filter((x) => x && x.name).map((x) => x.name),
    attacks,
  };
  for (const k of ['skillCD1', 'skillCD2', 'skillCD3', 'skillCD4']) if (p[k]) r[k] = p[k];
  return r;
}

const spawns = sceneSpawns();
const ids = new Set();
for (const lib of fs.readdirSync(RES)) {
  const d = path.join(RES, lib, 'scripts/export/monster');
  if (fs.existsSync(d)) for (const f of fs.readdirSync(d)) { const m = f.match(/^Monster(\d+)\.as$/); if (m) ids.add(+m[1]); }
}
const out = { _doc: 'Generated by tools/rig/extract_monsters.js from MonsterNN constructors. Units: original frames, px/frame. per_scene = values when spawned in that scene.', scenes: spawns, monsters: {} };
for (const id of [...ids].sort((a, b) => a - b)) {
  const inScenes = Object.entries(spawns).filter(([, s]) => s.spawns.some((x) => x.enemy === id)).map(([n]) => n);
  const home = ART_LIB[id] ? libStage(ART_LIB[id]) : inScenes.length ? sceneId(inScenes[0])[0] : 1;
  const cls = findClass(id, home);
  if (!cls) continue;
  const body = ctorToJs(fs.readFileSync(cls.file, 'utf8'), id);
  if (!body) continue;
  const entry = { lib: cls.lib, art_lib: ART_LIB[id] || null, scenes: inScenes, base: summarize(evaluate(body, { stage: home, level: 0 })), per_scene: {} };
  for (const sc of inScenes) {
    const [stage, level] = sceneId(sc);
    const c = findClass(id, stage);
    const b2 = c ? ctorToJs(fs.readFileSync(c.file, 'utf8'), id) : body;
    const v = summarize(evaluate(b2, { stage, level }));
    if (JSON.stringify(v) !== JSON.stringify(entry.base)) entry.per_scene[sc] = v;
  }
  out.monsters[id] = entry;
}
fs.writeFileSync(OUT, JSON.stringify(out, null, 1));
const errs = Object.entries(out.monsters).filter(([, m]) => m.base.error).map(([id, m]) => id + ': ' + m.base.error);
console.log('monsters', Object.keys(out.monsters).length, 'errors', errs.length, errs.join(' | '));
