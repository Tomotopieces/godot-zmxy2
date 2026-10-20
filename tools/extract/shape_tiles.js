// A level's art is drawn by the original as vector shapes whose fills are bitmaps (floor tiles, rock faces, scenery
// pieces): a shape is a set of rectangles, each showing a part of one bitmap. Rasterising the shape makes one huge
// picture whose abutting rectangles leave hairline seams; the pieces themselves are what the artist made.
//
//   decompose(libName, shapeId) -> null | [{ bitmap, x, y, w, h, u, v, su, sv }]
//     one entry per rectangle: stage position / size in px (shape-local), the bitmap id, the bitmap pixel (u, v) that
//     the rectangle's top-left corner shows, and the bitmap pixels per stage px (su, sv).
//     null when the shape is not made of bitmap rectangles only (curves, solid fills, slanted edges).
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const CR = String.fromCharCode(13);
const LF = String.fromCharCode(10);
const cache = {};

function load(lib) {
  return cache[lib] || (cache[lib] = fs.readFileSync(path.join(ROOT, 'decomp/xml', lib + '.xml'), 'utf8').split(CR + LF).join(LF));
}

function shapeXml(lib, id) {
  const x = load(lib);
  const re = new RegExp('<item type="DefineShape[0-9]?Tag"[^>]*shapeId="' + id + '">');
  const m = re.exec(x);
  if (!m) return null;
  return x.slice(m.index, x.indexOf(LF + '    </item>', m.index));
}

const attr = (s, n) => {
  const m = new RegExp('\\b' + n + '="(-?[0-9.]+)"').exec(s);
  return m ? +m[1] : undefined;
};

// the fill style table of a FILLSTYLEARRAY chunk: bitmap fills with their matrix, other fills as bitmap 65535
function parseStyles(s) {
  const out = [];
  const re = /<item type="FILLSTYLE"([^>]*)>(?:\s*<bitmapMatrix([^>]*)\/>)?/g;
  let m;
  while ((m = re.exec(s))) {
    const bid = /bitmapId="(\d+)"/.exec(m[1]);
    if (!bid || +bid[1] === 65535 || !m[2]) { out.push({ bitmap: 65535 }); continue; }
    // a rotated or mirrored bitmap is not a plain piece of it
    if (/hasRotate="true"/.test(m[2]) || attr(m[2], 'scaleX') <= 0 || attr(m[2], 'scaleY') <= 0) { out.push({ bitmap: 65535 }); continue; }
    out.push({ bitmap: +bid[1], sx: attr(m[2], 'scaleX'), sy: attr(m[2], 'scaleY'), tx: attr(m[2], 'translateX') || 0, ty: attr(m[2], 'translateY') || 0 });
  }
  return out;
}

function decompose(lib, id) {
  const xml = shapeXml(lib, id);
  if (!xml) return null;
  const at = xml.indexOf('<shapeRecords>');
  let styles = parseStyles(xml.slice(0, at));
  const parts = xml.slice(at).split(/(?=<item type="StyleChangeRecord")/);
  const out = [];
  let pos = [0, 0];
  for (const p of parts) {
    if (!p.startsWith('<item type="StyleChangeRecord"')) continue;
    const headTag = /<item type="StyleChangeRecord"[^>]*>/.exec(p)[0];
    const firstEdge = p.search(/<item type="(Straight|Curved)EdgeRecord"/);
    const ns = p.indexOf('<fillStyles type="FILLSTYLEARRAY">');
    if (ns >= 0 && (firstEdge < 0 || ns < firstEdge)) styles = parseStyles(p.slice(ns, firstEdge < 0 ? undefined : firstEdge));
    if (/stateMoveTo="true"/.test(headTag)) pos = [attr(headTag, 'moveDeltaX') || 0, attr(headTag, 'moveDeltaY') || 0];
    const edges = [...p.matchAll(/<item type="(StraightEdgeRecord|CurvedEdgeRecord)"([^>]*)>/g)];
    if (!edges.length) continue;
    if (edges.some((e) => e[1] === 'CurvedEdgeRecord')) return null;
    const fill = attr(headTag, 'fillStyle1') || attr(headTag, 'fillStyle0') || 0;
    const pts = [pos.slice()];
    let q = pos.slice();
    for (const e of edges) {
      q = [q[0] + (attr(e[2], 'deltaX') || 0), q[1] + (attr(e[2], 'deltaY') || 0)];
      pts.push(q.slice());
    }
    pos = q;
    const st = styles[fill - 1];
    if (!st || st.bitmap === 65535) return null;
    const xs = pts.map((v) => v[0]);
    const ys = pts.map((v) => v[1]);
    const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
    // an axis-aligned rectangle: every vertex is a corner of the bounding box
    if (!pts.every((v) => (v[0] === x0 || v[0] === x1) && (v[1] === y0 || v[1] === y1))) return null;
    out.push({ bitmap: st.bitmap, x: x0 / 20, y: y0 / 20, w: (x1 - x0) / 20, h: (y1 - y0) / 20, u: (x0 - st.tx) / st.sx, v: (y0 - st.ty) / st.sy, su: 20 / st.sx, sv: 20 / st.sy });
  }
  return out.length ? out : null;
}

module.exports = { decompose };

if (require.main === module) {
  const [lib, id] = process.argv.slice(2);
  const r = decompose(lib, id);
  console.log(r ? r.length + ' rects' : 'not decomposable');
  if (r) console.log(r.slice(0, 4));
}

// Like decompose(), but for a shape that mixes things: the rectangles of bitmap fills are returned (a mirrored bitmap has a
// negative su / sv), and whatever else the shape holds (solid or gradient fills, slanted or curved edges, rotated bitmaps)
// is listed in `skipped` with its bounds. Every rectangle is a piece of its own, in painting order.
function parseStylesLoose(s) {
  const out = [];
  const re = /<item type="FILLSTYLE"([^>]*)>(?:\s*<bitmapMatrix([^>]*)\/>)?/g;
  let m;
  while ((m = re.exec(s))) {
    const bid = /bitmapId="(\d+)"/.exec(m[1]);
    if (!bid || +bid[1] === 65535 || !m[2] || /hasRotate="true"/.test(m[2])) { out.push({ bitmap: 65535 }); continue; }
    out.push({ bitmap: +bid[1], sx: attr(m[2], 'scaleX'), sy: attr(m[2], 'scaleY'), tx: attr(m[2], 'translateX') || 0, ty: attr(m[2], 'translateY') || 0 });
  }
  return out;
}

function decomposeLoose(lib, id) {
  const xml = shapeXml(lib, id);
  if (!xml) return null;
  const at = xml.indexOf('<shapeRecords>');
  let styles = parseStylesLoose(xml.slice(0, at));
  const parts = xml.slice(at).split(/(?=<item type="StyleChangeRecord")/);
  const out = [];
  const skipped = [];
  let pos = [0, 0];
  for (const p of parts) {
    if (!p.startsWith('<item type="StyleChangeRecord"')) continue;
    const headTag = /<item type="StyleChangeRecord"[^>]*>/.exec(p)[0];
    const firstEdge = p.search(/<item type="(Straight|Curved)EdgeRecord"/);
    const ns = p.indexOf('<fillStyles type="FILLSTYLEARRAY">');
    if (ns >= 0 && (firstEdge < 0 || ns < firstEdge)) styles = parseStylesLoose(p.slice(ns, firstEdge < 0 ? undefined : firstEdge));
    if (/stateMoveTo="true"/.test(headTag)) pos = [attr(headTag, 'moveDeltaX') || 0, attr(headTag, 'moveDeltaY') || 0];
    const edges = [...p.matchAll(/<item type="(StraightEdgeRecord|CurvedEdgeRecord)"([^>]*)>/g)];
    if (!edges.length) continue;
    const curved = edges.some((e) => e[1] === 'CurvedEdgeRecord');
    const fill = attr(headTag, 'fillStyle1') || attr(headTag, 'fillStyle0') || 0;
    const pts = [pos.slice()];
    let q = pos.slice();
    for (const e of edges) {
      q = [q[0] + (attr(e[2], 'deltaX') || 0) + (attr(e[2], 'controlDeltaX') || 0) + (attr(e[2], 'anchorDeltaX') || 0), q[1] + (attr(e[2], 'deltaY') || 0) + (attr(e[2], 'controlDeltaY') || 0) + (attr(e[2], 'anchorDeltaY') || 0)];
      pts.push(q.slice());
    }
    pos = q;
    const st = styles[fill - 1];
    const xs = pts.map((v) => v[0]);
    const ys = pts.map((v) => v[1]);
    const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
    // a rectangle may be drawn with extra vertices on its sides (two edges one after the other in a direction): every edge is horizontal or vertical and every vertex lies on the box
    const rect = !curved && pts.every((v) => v[0] === x0 || v[0] === x1 || v[1] === y0 || v[1] === y1)
      && pts.every((v, i) => i === 0 || v[0] === pts[i - 1][0] || v[1] === pts[i - 1][1]);
    if (st && st.bitmap !== 65535 && rect && st.sx && st.sy) out.push({ bitmap: st.bitmap, x: x0 / 20, y: y0 / 20, w: (x1 - x0) / 20, h: (y1 - y0) / 20, u: (x0 - st.tx) / st.sx, v: (y0 - st.ty) / st.sy, su: 20 / st.sx, sv: 20 / st.sy });
    else skipped.push({ fill, st, rect, curved, x: x0 / 20, y: y0 / 20, w: (x1 - x0) / 20, h: (y1 - y0) / 20, edges: edges.length });
  }
  return { pieces: out, skipped };
}
module.exports.decomposeLoose = decomposeLoose;
