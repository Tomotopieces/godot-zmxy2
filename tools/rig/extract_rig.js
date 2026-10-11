// Flatten a Flash character/effect symbol into cutout-rig data for Godot.
//
// For every action (frame label of the root clip, or the whole timeline when there are no labels)
// the nested clip tree is simulated frame by frame. Each leaf is identified by its depth path
// (Flash draw order == lexicographic depth path), which becomes one Sprite2D track in Godot.
// Equipment selector clips (frame scripts calling getCurClothId/getCurWeaponId/getWingId) become
// "slot" leaves whose content is exported separately per equipment id.
//
// Output JSON (consumed by godot/tools/build_rigs.gd):
// {
//   name, fps, textures: {texKey: {file, ox, oy, scale}},
//   slots: {selId: {kind, offset, variants: {id: {frames:[[leaf]], loop}}}},
//   actions: {label: {frames, loop, tracks: [{path, kind, keys:[[f, texKey|selId|null, m, ct]]}],
//                     hit: [[f, rect|null]], hurt: [[f, rect|null]], markers: {name: [[f, x, y]]},
//                     events: [[f, src]] }},
//   unknownScripts: [...]
// }
'use strict';
const fs = require('fs');
const path = require('path');
const { FlashLib, ROOT, I, mul, rectXf, union, CT_ID, ctMul } = require('./flash_data');
const { classifyEvents } = require('./events');

// ------------------------------------------------------------------ script classification

const SEL_RE = /getCurClothId\(\) > 2|gotoAndPlay\(BaseHero\(this\.to\.parent\)\.(getCurClothId|getCurWeaponId|getWingId)\(\)( - 2)?\)|getEquipNum\(\); (?:if\([^)]*\) \{ )?this\.gotoAndPlay\(this\.obj\.(zbfj|zbwq|zbcb)\)|gotoAndStop\(Monster45\(this\.parent\.parent\)\.(getCurrentForm)\(\)\)|gotoAndStop\(7 - Monster51\(this\.parent\.parent\)\.(getRoundValue)\(\)\)/;

// 唐僧's torso pieces sit in a clip named bodyEquip whose frame is the worn clothes id (Role2.setEquips); it is a cloth selector
function selectorOf(lib, e) { return e.name === 'bodyEquip' ? 'cloth' : selectorKind(lib, e.c); }

function selectorKind(lib, id) {
  const fsc = lib.frameScripts(id);
  // the selector script is normally on frame 1; some bag portrait pieces only read the user's look on a later frame
  const s1 = fsc[1] || Object.values(fsc).find((x) => SEL_RE.test(x));
  if (!s1) return null;
  const m = s1.match(SEL_RE);
  if (!m) return null;
  if (/getCurClothId\(\) > 2/.test(s1)) return 'cloth_ex';     // frame = clothId - 2, hidden when clothId <= 2
  if (m[3]) return { zbfj: 'cloth', zbwq: 'weapon', zbcb: 'wing' }[m[3]];   // bag portrait (User.getEquipNum)
  if (m[5]) return 'round';   // 转轮王 form 2's ring counter: frame = 7 - rings left
  if (m[4]) return 'form';   // 白骨精 wings: frame = current form (Monster45.getCurrentForm)
  return { getCurClothId: 'cloth', getCurWeaponId: 'weapon', getWingId: 'wing' }[m[1]];
}

// nested (non-body) clip scripts: returns {op, arg} | null(no effect) | {op:'unknown'}
function classifyNested(src) {
  const s = src.replace(/\s+/g, ' ').trim();
  if (/^((this\.)?stop\(\);? ?)+$/.test(s)) return { op: 'stop' };
  let m = s.match(/^(this\.)?(gotoAndPlay|gotoAndStop)\((\d+|"[^"]*")\);?( stop\(\);)?$/);
  if (m) return { op: m[2], arg: m[3].startsWith('"') ? m[3].slice(1, -1) : +m[3] };
  if (/^(if\((this\.)?parent\) \{ )?(this\.)?parent\.removeChild\(this\);( \})?( stop\(\);)?$/.test(s)) return { op: 'remove' };
  return { op: 'unknown', src: s };
}

// ------------------------------------------------------------------ simulation

class Inst {
  constructor(sim, id, owner) {
    this.sim = sim; this.lib = sim.lib; this.id = id; this.owner = owner;
    this.spr = this.lib.sprite(id);
    this.frame = 0; this.playing = true; this.born = true;
    this.kids = new Map();      // depth -> {iid, node}
    this.removed = new Map();   // depth -> iid removed by script
    this.scripts = this.lib.frameScripts(id);
    this.isBody = false;
    this.build();
    this.queue();
  }
  get n() { return this.spr ? this.spr.n : 1; }
  build() {
    const fr = (this.spr && this.spr.frames[this.frame]) || [];
    const seen = new Set();
    for (const e of fr) {
      seen.add(e.d);                    // mask layers (e.clip) are kept: they crop the layers above them
      const k = this.kids.get(e.d);
      if (k && k.iid === e.i) { k.e = e; continue; }
      if (this.removed.get(e.d) === e.i) continue;
      this.removed.delete(e.d);
      const node = !e.clip && this.lib.sprite(e.c) && !selectorOf(this.lib, e) && e.name !== 'colipse'
        ? new Inst(this.sim, e.c, this) : null;
      this.kids.set(e.d, { iid: e.i, e, node });
    }
    for (const d of [...this.kids.keys()]) if (!seen.has(d)) this.kids.delete(d);
    for (const d of [...this.removed.keys()]) if (!seen.has(d)) this.removed.delete(d);
  }
  queue() { if (this.scripts[this.frame + 1]) this.sim.queue.push([this, this.frame]); }
  advance() {
    if (!this.born && this.playing && this.n > 1) {
      this.frame = (this.frame + 1) % this.n;
      this.build();
      this.queue();
    }
    this.born = false;
    for (const k of this.kids.values()) if (k.node) k.node.advance();
  }
  goto(f, play) {
    const t = typeof f === 'string' ? this.spr.labels[f] : f - 1;
    this.playing = play;
    if (t === undefined || t < 0 || t >= this.n || t === this.frame) return;
    this.frame = t; this.build(); this.queue();
  }
  runScript(f) {
    if (f !== this.frame) return;
    const src = this.scripts[f + 1];
    if (this.isBody) { this.sim.bodyScript(f, src); return; }
    const c = classifyNested(src);
    if (c.op === 'stop') this.playing = false;
    else if (c.op === 'gotoAndPlay') this.goto(c.arg, true);
    else if (c.op === 'gotoAndStop') this.goto(c.arg, false);
    else if (c.op === 'remove') {
      const p = this.owner;
      for (const [d, k] of p.kids) if (k.node === this) { p.removed.set(d, k.iid); p.kids.delete(d); break; }
    } else if (/this.parent/.test(c.src)) this.sim.events.push([this.sim.frameIndex, c.src]);   // nested clip talking to its owner
    else this.sim.unknown(this.lib.className(this.id) || 'c' + this.id, f + 1, c.src);
  }
}

class Sim {
  constructor(lib, rootId, rootFrame, rootPlays) {
    this.lib = lib; this.queue = []; this.events = []; this.ended = -1; this.held = -1; this.unknowns = [];
    this.frameIndex = 0;
    this.root = new Inst(this, rootId, null);
    this.root.goto(rootFrame + 1, rootPlays);
    this.root.playing = rootPlays;
    this.queue = this.queue.filter(([c]) => c !== this.root || rootPlays);
    // the "body" child carries the action timeline and its scripts are gameplay events
    for (const k of this.root.kids.values()) if (k.e.name === 'body' && k.node) { this.body = k.node; k.node.isBody = true; }
    // AUTO_BODY=1: a labelled root whose label frames hold one unnamed animated clip each (magic treasures)
    if (!this.body && !rootPlays && process.env.AUTO_BODY) {
      const ks = [...this.root.kids.values()].filter((k) => k.node);
      if (ks.length === 1) { this.body = ks[0].node; this.body.isBody = true; }
    }
    if (!this.body && rootPlays) { this.body = this.root; this.root.isBody = true; }
    this.flush();
    // everything constructed before the first tick is already on stage: it advances on tick 1
    const unborn = (n) => { n.born = false; for (const k of n.kids.values()) if (k.node) unborn(k.node); };
    unborn(this.root);
  }
  flush() { let g = 0; while (this.queue.length && g++ < 10000) { const q = this.queue; this.queue = []; for (const [c, f] of q) c.runScript(f); } }
  tick() { this.root.advance(); this.flush(); }
  bodyScript(f, src) {
    this.events.push([this.frameIndex, src]);
    // action end: script changes curAction / plays another label / stops at top level
    const top = (() => { let s = src, p; do { p = s; s = s.replace(/\{[^{}]*\}/g, ''); } while (s !== p); return s; })();
    if ((/\.curAction = /.test(src) || /\.gotoAndStop\("/.test(src) || /removeChild\(this\)/.test(src) || /\.destroy\(\)/.test(src) || /BossDead/.test(src)) && this.ended < 0 && this.frameIndex >= (this.endFrom || 0)) this.ended = this.frameIndex;
    if (/(^|[;}\s])(this\.)?stop\(\);/.test(top)) { this.body.playing = false; if (this.held < 0) this.held = this.frameIndex; }
  }
  unknown(cls, f, src) { this.unknowns.push(`${cls} f${f}: ${src.slice(0, 160)}`); }

  // flatten current display state -> leaves
  snapshot() {
    const leaves = [], rects = { hit: null, hurt: null }, markers = {};
    // fl = Flash filters inherited from ancestors, fg = path of the outermost filtered ancestor (filter group)
    // cl = crop rect in rig space from Flash mask layers (rectangular masks: sprite sheets, gauges)
    const walk = (inst, m, ct, pathArr, inBody, fl = [], fg = null, cl = null, bm = 0) => {
      const masks = [];
      for (const [d, k] of [...inst.kids].sort((a, b) => a[0] - b[0])) {
        const e = k.e;
        const mm = mul(m, e.m);
        const cc = e.ct ? ctMul(ct, e.ct) : ct;
        const p = pathArr.concat(d);
        const eb = e.blend || bm;   // Flash blend mode (8 = add), inherited by the clip's children
        // HIDE_AT=action:path:frame,...: a sub-tree that is gone from this frame on (a skill part replaced by the next one)
        if (this.hideAt && this.hideAt.some(([pp, ff]) => (p.join('.') + '.').startsWith(pp + '.') && this.frameIndex >= ff)) continue;
        if (e.clip) {
          const b = boundsOf(this.lib, e.c);
          if (b) masks.push({ until: e.clip, m: mm, b });   // oriented: it lives in the space of the clip that holds it
          continue;
        }
        let ec = cl;
        for (const mk of masks) if (d <= mk.until) ec = (ec || []).concat([mk]);
        const ef = e.filters && e.filters.length ? fl.concat(e.filters) : fl;
        const eg = ef !== fl && !fg ? p.join('.') : fg;
        if (e.name === 'colipse') {
          const b = boundsOf(this.lib, e.c);
          if (b) rects.hurt = union(rects.hurt, rectXf(mm, b));
          continue;
        }
        // stick = attack area. Skill sticks are the visible effect animation itself (hit tests are per pixel),
        // so it plays and draws like any clip; the hit rect follows its current frame.
        if (/^stick[0-9]*$/.test(e.name || '')) {
          const from = leaves.length;
          if (k.node) walk(k.node, mm, cc, p, inBody, ef, eg, ec, eb);
          else if (this.lib.texture(e.c)) leaves.push({ path: p, kind: 'tex', ref: e.c, m: mm, ct: cc, fl: ef, fg: eg, cl: clipIn(ec, mm), bm: eb });
          let r = null;
          // (where the picture is visible: a sparkle drawn on a big transparent texture must not make the hit box that big)
          for (const lf of leaves.slice(from)) { const b = lf.kind === 'tex' ? visibleBounds(this.lib, lf.ref, 12) : null; if (b) r = union(r, rectXf(lf.m, lf.cl ? intersectR(b, lf.cl) : b)); }
          if (!r) { const b = boundsOf(this.lib, e.c); if (b) r = rectXf(mm, b); }
          if (r) rects.hit = union(rects.hit, r);
          continue;
        }
        const sk = selectorOf(this.lib, e);
        if (sk) { leaves.push({ path: p, kind: 'slot', ref: e.c, sel: sk, m: mm, ct: cc, fl: ef, fg: eg, cl: clipIn(ec, mm), bm: eb }); continue; }
        if (k.node) {
          if (e.name && e.name !== 'body') markers[e.name] = [mm[4], mm[5]];
          // anchors for effects the game plays on demand (level-up glow) are not part of the rig art
          if (!SEPARATE_CLIPS.has(e.name)) walk(k.node, mm, cc, p, inBody || e.name === 'body', ef, eg, ec, eb);
          continue;
        }
        if (this.lib.texture(e.c)) leaves.push({ path: p, kind: 'tex', ref: e.c, m: mm, ct: cc, fl: ef, fg: eg, cl: clipIn(ec, mm), bm: eb });
        else if (this.lib.J.texts && this.lib.J.texts[e.c]) leaves.push({ path: p, kind: 'text', ref: e.c, m: mm, ct: cc, fl: ef, fg: eg, cl: clipIn(ec, mm), bm: eb });
      }
    };
    walk(this.root, I, CT_ID, [], false, this.rootFilters || [], this.rootFilters && this.rootFilters.length ? 'root' : null);
    let art = null;
    // the art box (what an effect without hit sticks hits with) is where the picture is visible: the original tests
    // against the drawn pixels, and a texture's transparent margin or soft glow must not count
    for (const lf of leaves) { const b = lf.kind === 'tex' ? visibleBounds(this.lib, lf.ref) : null; if (b) { let r = rectXf(lf.m, lf.cl ? intersectR(b, lf.cl) : b); if (r.w > 0 && r.h > 0) art = union(art, r); } }
    return { leaves, rects, markers, art };
  }
}

// The crop a list of Flash masks puts on a layer with matrix m, as a rect in that layer's own space (before m). A mask
// is rectangular in the space of the clip that holds it; the layer is usually shifted inside that clip (a sprite sheet
// scrolling under its window), so relative to the layer it is an upright rect even when the clip is turned.
function clipIn(list, m) {
  if (!list) return null;
  const det = m[0] * m[3] - m[1] * m[2];
  if (Math.abs(det) < 1e-9) return null;
  const inv = [m[3] / det, -m[1] / det, -m[2] / det, m[0] / det, 0, 0];
  inv[4] = -(inv[0] * m[4] + inv[2] * m[5]);
  inv[5] = -(inv[1] * m[4] + inv[3] * m[5]);
  let r = null;
  for (const mk of list) { const rr = rectXf(mul(inv, mk.m), mk.b); r = r ? intersectR(r, rr) : rr; }
  return r;
}

function intersectR(a, b) {
  const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y);
  const r = Math.min(a.x + a.w, b.x + b.w), btm = Math.min(a.y + a.h, b.y + b.h);
  return { x, y, w: Math.max(0, r - x), h: Math.max(0, btm - y) };
}

const PNG = require('./png');
const visCache = new Map();
// bounds (local units) of the pixels of a leaf texture that are visibly opaque
function visibleBounds(lib, c, thr = 48) {
  const t = lib.texture(c);
  if (!t) return boundsOf(lib, c);
  const key = t.file + '|' + thr;
  if (!visCache.has(key)) {
    let r = null;
    try {
      const im = PNG.decode(t.file);
      let x0 = im.width, y0 = im.height, x1 = -1, y1 = -1;
      for (let y = 0; y < im.height; y++) for (let x = 0; x < im.width; x++) if (im.data[(y * im.width + x) * 4 + 3] >= thr) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
      if (x1 >= 0) r = { x: t.ox + x0 / t.scale, y: t.oy + y0 / t.scale, w: (x1 + 1 - x0) / t.scale, h: (y1 + 1 - y0) / t.scale };
    } catch (e) { r = null; }
    visCache.set(key, r);
  }
  return visCache.get(key) || boundsOf(lib, c);
}

function boundsOf(lib, c, depth = 0) {
  if (lib.J.shapes[c]) return lib.J.shapes[c];
  if (lib.J.images[c]) return { x: 0, y: 0, w: lib.J.images[c].w, h: lib.J.images[c].h };
  const s = lib.sprite(c);
  if (!s || depth > 12) return null;
  let b = null;
  for (const e of s.frames[0] || []) { if (e.clip) continue; const cb = boundsOf(lib, e.c, depth + 1); if (cb) b = union(b, rectXf(e.m, cb)); }
  return b;
}

// ------------------------------------------------------------------ selector variants

// The content of a selector clip at a given frame (static), or a looping frame range (wing).
function variantFrames(lib, selId, kind) {
  const spr = lib.sprite(selId);
  const out = {};
  const leafAt = (frame) => {
    const leaves = [];
    const walk = (id, f, m, ct, pathArr, fl = [], fg = null) => {
      const s = lib.sprite(id);
      const fr = (s && s.frames[Math.min(f, s.n - 1)]) || [];
      for (const e of [...fr].sort((a, b) => a.d - b.d)) {
        if (e.clip) continue;
        const mm = mul(m, e.m), cc = e.ct ? ctMul(ct, e.ct) : ct, p = pathArr.concat(e.d);
        const ef = e.filters && e.filters.length ? fl.concat(e.filters) : fl;
        const eg = ef !== fl && !fg ? p.join('.') : fg;
        if (lib.sprite(e.c)) walk(e.c, 0, mm, cc, p, ef, eg);
        else if (lib.texture(e.c)) leaves.push({ path: p, kind: 'tex', ref: e.c, m: mm, ct: cc, fl: ef, fg: eg });
      }
    };
    walk(selId, frame, I, CT_ID, []);
    return leaves;
  };
  if (kind === 'wing') {
    // wing ids are loop start frames; each loop runs until the next frame carrying a script
    const scripted = Object.keys(lib.frameScripts(selId)).map(Number).sort((a, b) => a - b);
    for (let i = 0; i < scripted.length; i++) {
      const start = scripted[i];
      const end = i + 1 < scripted.length ? scripted[i + 1] - 1 : spr.n;
      if (start === 1) { out[1] = { frames: [leafAt(0)], loop: false }; continue; }
      const id = start === 21 ? 3 : start;   // BaseHero.getWingId: zbcb 3 -> frame 21
      // nested wing clips animate by themselves: simulate the inner clip over the range
      const frames = [];
      for (let f = start - 1; f < end; f++) frames.push(simulateRange(lib, selId, f, start - 1));
      out[id] = { frames, loop: true };
    }
  } else if (kind === 'round') {
    // the counter holds its frame, but the rings inside keep turning: loop their clip
    const period = Math.max(1, ...spr.frames.flat().map((e) => (lib.sprite(e.c) || { n: 1 }).n));
    for (let f = 0; f < spr.n; f++) {
      const frames = [];
      for (let a = 0; a < period; a++) frames.push(simulateRange(lib, selId, f, f - a));
      out[f + 1] = { frames: frames.some((fr) => fr.length) ? frames : [[]], loop: true };
    }
  } else {
    for (let f = 0; f < spr.n; f++) {
      const leaves = leafAt(f);
      const id = kind === 'cloth_ex' ? f + 3 : f + 1;
      out[id] = { frames: [leaves], loop: false };
    }
  }
  return out;
}

// leaves of selector `selId` at timeline frame f, with nested clips aged (f - start) frames
function simulateRange(lib, selId, f, start) {
  const age = f - start;
  const leaves = [];
  const walk = (id, frame, m, ct, pathArr, fl = [], fg = null) => {
    const s = lib.sprite(id);
    const fr = (s && s.frames[frame % s.n]) || [];
    for (const e of [...fr].sort((a, b) => a.d - b.d)) {
      if (e.clip) continue;
      const mm = mul(m, e.m), cc = e.ct ? ctMul(ct, e.ct) : ct, p = pathArr.concat(e.d);
      const ef = e.filters && e.filters.length ? fl.concat(e.filters) : fl;
      const eg = ef !== fl && !fg ? p.join('.') : fg;
      if (lib.sprite(e.c)) walk(e.c, age, mm, cc, p, ef, eg);
      else if (lib.texture(e.c)) leaves.push({ path: p, kind: 'tex', ref: e.c, m: mm, ct: cc, fl: ef, fg: eg });
    }
  };
  walk(selId, f, I, CT_ID, []);
  return leaves;
}

// ------------------------------------------------------------------ main

// named child clips the game handles itself: effects played on demand (level-up glow), and the other
// characters' layers of shared effects (WsEffect hides Role2Mc / Role3Mc for Wukong)
const SEPARATE_CLIPS = new Set(['levelupmc', 'Role2Mc', 'Role3Mc', 'pointMc']);   // pointMc: the hub selector's pointer is its own rig (hub_pointer)

// rootFilters: filters of the placement this symbol normally has (e.g. levelupmc's hue shift inside the hero)
function extract(libName, cls, outName, rootFilters = []) {
  const lib = new FlashLib(libName);
  // '#<id>' = unnamed symbol; '@<frame>' = start playing at that frame index (clips that stop() until play())
  const [clsName, startAt] = cls.split('@');
  const startFrame = startAt ? +startAt : 0;
  const rootId = clsName.startsWith('#') ? +clsName.slice(1) : lib.byClass[clsName];
  if (rootId === undefined) throw new Error('class not found: ' + cls);
  const root = lib.sprite(rootId);
  const out = { name: outName, lib: libName, cls, fps: lib.fps, textures: {}, slots: {}, actions: {}, filters: [], unknownScripts: [] };
  // Flash filter lists -> ids into out.filters (blur sizes / glow / color matrix as authored)
  const filterIds = new Map();
  const filterId = (fl) => {
    if (!fl || !fl.length) return null;
    const norm = fl.map((x) => x.t === 'COLORMATRIXFILTER' ? { t: 'matrix', m: x.matrix }
      : x.t === 'BLURFILTER' ? { t: 'blur', x: x.blurX, y: x.blurY, q: x.passes || 1 }
      : { t: 'glow', x: x.blurX, y: x.blurY, s: x.strength, c: x.color, inner: x.innerGlow === 'true', knockout: x.knockout === 'true' });
    const k = JSON.stringify(norm);
    if (!filterIds.has(k)) { filterIds.set(k, out.filters.length); out.filters.push(norm); }
    return filterIds.get(k);
  };
  const texKey = (c) => {
    const k = libName + ':' + c;
    if (!out.textures[k]) {
      const t = lib.texture(c);
      if (t) out.textures[k] = t;
    }
    return k;
  };
  const r3 = (v) => Math.round(v * 1000) / 1000;
  const fmtM = (m) => m.map(r3);
  const fmtCt = (ct) => (ct.every((v, i) => v === CT_ID[i]) ? null : ct.map(r3));
  const fmtR = (r) => r && [r.x, r.y, r.w, r.h].map((v) => Math.round(v * 10) / 10);

  const labels = Object.entries(root.labels).sort((a, b) => a[1] - b[1]);
  // FRAME_ACTIONS=1: a clip whose every frame holds still (stop()) becomes one single-frame action "f0", "f1" ... per frame
  const actions = process.env.FRAME_ACTIONS ? Array.from({ length: root.n }, (_, f) => ({ label: 'f' + f, f, plays: false }))
    : labels.length ? labels.map(([l, f]) => ({ label: l, f, plays: false })) : [{ label: 'default', f: startFrame, plays: !process.env.ROOT_STOPPED }];   // ROOT_STOPPED=1: the root holds its frame (gotoAndStop), only nested clips run

  for (const act of actions) {
    const sim = new Sim(lib, rootId, act.f, act.plays);
    sim.rootFilters = rootFilters;
    sim.hideAt = (process.env.HIDE_AT || '').split(',').filter(Boolean).map((x) => x.split(':')).filter((x) => x[0] === act.label).map((x) => [x[1], +x[2]]);
    // END_FROM=action:frame,...: scripts that merely switch to another action before this frame do not end the action
    sim.endFrom = +(((process.env.END_FROM || '').split(',').map((x) => x.split(':')).find((x) => x[0] === act.label) || [])[1] || 0);
    let bodyN = sim.body && sim.body !== sim.root ? sim.body.n : (act.plays ? root.n - act.f : 1);
    // a single-frame container whose children animate (e.g. portals): capture the longest child loop
    if (act.plays && root.n === 1) {
      const longest = (id, d = 0) => { const sp = lib.sprite(id); if (!sp || d > 8) return 1; let n = sp.n; for (const fr of sp.frames) for (const e of fr) n = Math.max(n, longest(e.c, d + 1)); return n; };
      bodyN = Math.min(longest(rootId), 240);
    }
    // HOLD_FRAMES=n: keep simulating a stopped timeline whose nested clips still loop (held poses)
    if (process.env.HOLD_FRAMES) bodyN = Math.max(bodyN, +process.env.HOLD_FRAMES);
    // DEAD_FRAMES=n: the dead pose is a nested clip (blink + BossDead script) on a single frame of the root: run it for n frames
    if (process.env.DEAD_FRAMES && act.label === 'dead') bodyN = Math.max(bodyN, +process.env.DEAD_FRAMES);
    const tracks = new Map();   // pathKey -> track
    const hit = [], hurt = [], art = [], markers = {};
    let frames = 0;
    for (let f = 0; f < bodyN; f++) {
      sim.frameIndex = f;
      if (f > 0) sim.tick();
      else sim.flush();
      const snap = sim.snapshot();
      for (const lf of snap.leaves) {
        const fid = filterId(lf.fl);
        const pk = lf.path.join('.') + ':' + lf.kind + (fid === null ? '' : '|f' + fid) + (lf.bm ? '|b' + lf.bm : '');
        let tr = tracks.get(pk);
        if (!tr) { tr = { path: lf.path, kind: lf.kind, keys: [], filter: fid, group: fid === null ? null : lf.fg, blend: lf.bm || 0 }; tracks.set(pk, tr); }
        const ref = lf.kind === 'tex' ? texKey(lf.ref) : lf.kind === 'slot' ? lf.ref : libName + ':text:' + lf.ref;
        if (lf.kind === 'slot' && !out.slots[lf.ref]) out.slots[lf.ref] = { kind: lf.sel, variants: null };
        tr.keys.push(lf.cl ? [f, ref, fmtM(lf.m), fmtCt(lf.ct), fmtR(lf.cl)] : [f, ref, fmtM(lf.m), fmtCt(lf.ct)]);
      }
      for (const tr of tracks.values()) {
        const last = tr.keys[tr.keys.length - 1];
        if (last[0] !== f && last[1] !== null) tr.keys.push([f, null, null, null]);  // hidden this frame
      }
      // HIT_MAX_X=action:x,...: the attack box never reaches behind x (art faces left: x < 0 is the front)
      let hr = fmtR(snap.rects.hit);
      const cap = ((process.env.HIT_MAX_X || '').split(',').map((q) => q.split(':')).find((q) => q[0] === act.label) || [])[1];
      if (hr && cap !== undefined && hr[0] + hr[2] > +cap) hr = hr[0] >= +cap ? null : [hr[0], hr[1], Math.round((+cap - hr[0]) * 10) / 10, hr[3]];
      hit.push([f, hr]);
      art.push([f, fmtR(snap.art)]);
      hurt.push([f, fmtR(snap.rects.hurt)]);
      for (const [n, p] of Object.entries(snap.markers)) (markers[n] ||= []).push([f, r3(p[0]), r3(p[1])]);
      frames = f + 1;
      if (sim.ended >= 0) break;
      if (sim.held >= 0 && f > sim.held && !process.env.HOLD_FRAMES) break;
    }
    // compact: drop consecutive duplicate keys
    const trackList = [...tracks.values()].sort((a, b) => cmpPath(a.path, b.path)).map((t) => {
      const keys = [];
      for (const k of t.keys) {
        const p = keys[keys.length - 1];
        if (p && JSON.stringify(p.slice(1)) === JSON.stringify(k.slice(1))) continue;
        keys.push(k);
      }
      return { path: t.path.join('.'), kind: t.kind, keys, filter: t.filter, group: t.group, blend: t.blend || undefined };
    });
    const compactR = (arr) => arr.filter((k, i) => i === 0 || JSON.stringify(k[1]) !== JSON.stringify(arr[i - 1][1]));
    const evs = sim.events.filter(([f]) => f < frames).flatMap(([f, src]) => classifyEvents(src, lib.fps).map((e) => [f, ...e]));
    out.actions[act.label] = {
      frames,
      loop: !process.env.LOOP_FROM && ((sim.ended < 0 && sim.held < 0) || !!process.env.HOLD_FRAMES),
      // LOOP_FROM=f: play once, then keep looping frames f.. (an opening followed by a nested clip's loop)
      loop_from: process.env.LOOP_FROM ? +process.env.LOOP_FROM : undefined,
      tracks: trackList,
      hit: compactR(hit), hurt: compactR(hurt), art: compactR(art),
      markers,
      events: evs.filter((e) => e[1] !== 'vis' && e[1] !== 'unknown').filter((e) => !(e[1] === 'finished' && e[0] < (sim.endFrom || 0))),
      // the body shown / hidden: becomes a visibility track of the parts, not an event
      rootvis: evs.filter((e) => e[1] === 'vis').map((e) => [e[0], e[2]]),
    };
    for (const e of evs) if (e[1] === 'unknown') out.unknownScripts.push(e[2]);
    out.unknownScripts.push(...sim.unknowns);
  }
  for (const sel of Object.keys(out.slots)) {
    const kind = out.slots[sel].kind;
    const vars = variantFrames(lib, +sel, kind);
    const vout = {};
    for (const [id, v] of Object.entries(vars)) {
      vout[id] = { loop: v.loop, frames: v.frames.map((fr) => fr.map((lf) => [lf.path.join('.'), texKey(lf.ref), fmtM(lf.m), fmtCt(lf.ct), filterId(lf.fl), filterId(lf.fl) === null ? null : lf.fg])) };
    }
    out.slots[sel].variants = vout;
  }
  out.unknownScripts = [...new Set(out.unknownScripts)];
  return out;
}

function cmpPath(a, b) {
  for (let i = 0; i < Math.min(a.length, b.length); i++) if (a[i] !== b[i]) return a[i] - b[i];
  return a.length - b.length;
}

module.exports = { extract };

if (require.main === module) {
  // optional 5th arg: "<lib>:<class>:<child name>" whose placement filters apply to the whole rig
  const [libName, cls, outName, outFile, filtersFrom] = process.argv.slice(2);
  let rootFilters = [];
  if (filtersFrom) {
    const [fl, fc, fn] = filtersFrom.split(':');
    const L2 = new FlashLib(fl);
    const host = L2.sprite(L2.byClass[fc]);
    const e = host && host.frames[0].find((x) => x.name === fn);
    rootFilters = (e && e.filters) || [];
  }
  const data = extract(libName, cls, outName, rootFilters);
  // textures are copied into the Godot project next to the rig: <outDir>/tex/<lib>_<id>.png
  const outDir = path.dirname(outFile);
  const texDir = path.join(outDir, 'tex');
  fs.mkdirSync(texDir, { recursive: true });
  const resDir = 'res://' + path.relative(path.join(ROOT, 'game'), texDir).split(path.sep).join('/');
  for (const [k, t] of Object.entries(data.textures)) {
    const fn = k.replace(':', '_') + path.extname(t.file);
    const dst = path.join(texDir, fn);
    if (!fs.existsSync(dst) || fs.statSync(dst).size !== fs.statSync(t.file).size) fs.copyFileSync(t.file, dst);
    t.res = resDir + '/' + fn;
    delete t.file;
  }
  fs.writeFileSync(outFile, JSON.stringify(data));
  const A = data.actions;
  console.log(outName, 'fps', data.fps, 'textures', Object.keys(data.textures).length, 'slots', Object.keys(data.slots).length);
  for (const [l, a] of Object.entries(A)) console.log(` ${l.padEnd(10)} frames ${String(a.frames).padStart(3)} loop ${a.loop ? 'Y' : '-'} tracks ${a.tracks.length} hitKeys ${a.hit.length} events ${a.events.length} markers ${Object.keys(a.markers).join(',')}`);
  if (data.unknownScripts.length) console.log('UNKNOWN nested scripts:\n  ' + data.unknownScripts.slice(0, 20).join('\n  '));
}
