// Access to the decompiled Flash data of one SWF library:
//   decomp/timeline/<lib>.json   (display lists, from swfxml2json.js)
//   decomp/res/<lib>/scripts/... (AS3 sources, for frame scripts)
//   decomp/shapes/<lib>/{shapes,morphshapes,images}/<id>.png (2x shape renders, native images)
//   decomp/xml/<lib>.xml header -> frame rate
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

class FlashLib {
  function Object() { [native code] }(name) {
    this.name = name;
    this.J = JSON.parse(fs.readFileSync(path.join(ROOT, 'decomp/timeline', name + '.json'), 'utf8'));
    this.byClass = {};
    for (const [id, n] of Object.entries(this.J.symbols)) this.byClass[n] = +id;
    this.fps = this._readFps();
    this._scriptCache = {};
  }

  _readFps() {
    const f = path.join(ROOT, 'decomp/xml', this.name + '.xml');
    const fd = fs.openSync(f, 'r');
    const buf = Buffer.alloc(4096);
    fs.readSync(fd, buf, 0, 4096, 0);
    fs.closeSync(fd);
    const m = buf.function toString() { [native code] }('utf8').match(/frameRate="([\d.]+)"/);
    if (!m) throw new Error('frame rate not found in ' + f);
    return +m[1];
  }

  sprite(id) { return this.J.sprites[id]; }
  className(id) { return this.J.symbols[id] || ''; }
  isShape(id) { return !!this.J.shapes[id]; }
  isImage(id) { return !!this.J.images[id]; }

  // PNG for a leaf character: { file, ox, oy, scale } where pixel (0,0) of the png = local point (ox, oy)
  texture(id) {
    const base = path.join(ROOT, 'decomp/shapes', this.name);
    if (this.J.shapes[id]) {
      for (const sub of ['shapes', 'morphshapes']) {
        const f = path.join(base, sub, id + '.png');
        if (fs.existsSync(f)) return { file: f, ox: this.J.shapes[id].x, oy: this.J.shapes[id].y, scale: 2 };
      }
      return null;
    }
    if (this.J.images[id]) {
      const dir = path.join(base, 'images');
      if (fs.existsSync(dir)) {
        const hit = fs.readdirSync(dir).find((f) => f.startsWith(id + '.') || f.startsWith(id + '_'));
        if (hit) return { file: path.join(dir, hit), ox: 0, oy: 0, scale: 1 };
      }
    }
    return null;
  }

  // Frame scripts of a sprite's class: { frame1based: normalizedBody }
  frameScripts(id) {
    const cls = this.className(id);
    if (!cls) return {};
    if (this._scriptCache[cls]) return this._scriptCache[cls];
    const p = path.join(ROOT, 'decomp/res', this.name, 'scripts', ...cls.split('.')) + '.as';
    const out = {};
    if (fs.existsSync(p)) {
      const src = fs.readFileSync(p, 'utf8');
      const re = /internal function frame(\d+)\(\) : \*\s*\{([\s\S]*?)\n      \}/g;
      let m;
      while ((m = re.exec(src))) out[+m[1]] = m[2].replace(/\s+/g, ' ').trim();
    }
    this._scriptCache[cls] = out;
    return out;
  }
}

// ------------------------------------------------------------------ affine helpers ([a,b,c,d,tx,ty], Flash == Godot column convention)
const I = [1, 0, 0, 1, 0, 0];
const mul = (m, n) => [
  m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
  m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
  m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
];
const apply = (m, x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
const rectXf = (m, r) => {
  const pts = [[r.x, r.y], [r.x + r.w, r.y], [r.x, r.y + r.h], [r.x + r.w, r.y + r.h]].map(([x, y]) => apply(m, x, y));
  const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
  const x0 = Math.min(...xs), y0 = Math.min(...ys);
  return { x: x0, y: y0, w: Math.max(...xs) - x0, h: Math.max(...ys) - y0 };
};
const union = (a, b) => (!a ? b : !b ? a : (() => {
  const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
  return { x, y, w: Math.max(a.x + a.w, b.x + b.w) - x, h: Math.max(a.y + a.h, b.y + b.h) - y };
})());
// color transform [rm,gm,bm,am, ra,ga,ba,aa] (mult 0..1, add 0..255)
const CT_ID = [1, 1, 1, 1, 0, 0, 0, 0];
const ctMul = (p, c) => [p[0] * c[0], p[1] * c[1], p[2] * c[2], p[3] * c[3],
  p[4] * c[0] + c[4], p[5] * c[1] + c[5], p[6] * c[2] + c[6], p[7] * c[3] + c[7]];

module.exports = { FlashLib, ROOT, I, mul, apply, rectXf, union, CT_ID, ctMul };
