// Convert an FFDec -swf2xml dump into a compact timeline JSON:
//   symbols: { charId: className }
//   sprites: { id: { n: frameCount, labels: {label: frameIndex0}, frames: [[{d,c,name,m:[a,b,c,d,tx,ty]}]] } }
//   shapes/images/texts: { id: {x,y,w,h} }   (bounds in pixels)
// Usage: node --max-old-space-size=8192 swfxml2json.js in.xml out.json
const fs = require('fs');
const { XMLParser } = require('fast-xml-parser');

const [inFile, outFile] = process.argv.slice(2);
const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '', isArray: (name) => name === 'item' });
const doc = parser.parse(fs.readFileSync(inFile, 'utf8'));
const tags = doc.swf.tags.item;

const T = 20; // twips per pixel
const out = { symbols: {}, sprites: {}, shapes: {}, images: {}, texts: {}, edits: {}, buttons: {} };

function rect(r) {
  if (!r) return null;
  const x0 = +r.Xmin / T, x1 = +r.Xmax / T, y0 = +r.Ymin / T, y1 = +r.Ymax / T;
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}
function matrix(m) {
  if (!m) return null;
  const a = m.hasScale === 'true' ? +m.scaleX : 1;
  const d = m.hasScale === 'true' ? +m.scaleY : 1;
  const b = m.hasRotate === 'true' ? +m.rotateSkew0 : 0;
  const c = m.hasRotate === 'true' ? +m.rotateSkew1 : 0;
  const r = (v) => Math.round(v * 10000) / 10000;
  return [r(a), r(b), r(c), r(d), +m.translateX / T, +m.translateY / T];
}

let instCounter = 0; // global instance id: changes whenever Flash would create a new display object instance
function simulateSprite(subTags) {
  const frames = []; const labels = {};
  const list = new Map(); // depth -> entry
  for (const t of subTags || []) {
    switch (t.type) {
      case 'PlaceObjectTag':
      case 'PlaceObject2Tag':
      case 'PlaceObject3Tag': {
        const d = +t.depth;
        const move = t.placeFlagMove === 'true';
        const hasChar = t.characterId !== undefined && (t.placeFlagHasCharacter === 'true' || t.type === 'PlaceObjectTag');
        let e = move && list.has(d) ? { ...list.get(d) } : { d, c: 0, m: [1, 0, 0, 1, 0, 0] };
        if (hasChar) {
          // new placement or character replacement => new instance (nested timelines restart)
          e = { d, c: +t.characterId, m: move ? e.m : [1, 0, 0, 1, 0, 0], i: ++instCounter };
          if (move && list.has(d)) { const o = list.get(d); if (o.name) e.name = o.name; if (o.ct) e.ct = o.ct; }
        }
        if (t.matrix) e.m = matrix(t.matrix);
        if (t.placeFlagHasName === 'true' || t.name !== undefined) e.name = t.name;
        if (t.placeFlagHasColorTransform === 'true' && t.colorTransform) {
          const ct = t.colorTransform;
          // normalized: multipliers in 0..1 (Flash 256 = 1.0), add terms in 0..255
          const mu = (v) => (v === undefined ? 1 : +v / 256), ad = (v) => (v === undefined ? 0 : +v);
          e.ct = [mu(ct.redMultTerm), mu(ct.greenMultTerm), mu(ct.blueMultTerm), mu(ct.alphaMultTerm), ad(ct.redAddTerm), ad(ct.greenAddTerm), ad(ct.blueAddTerm), ad(ct.alphaAddTerm)];
        }
        if (t.placeFlagHasClipDepth === 'true') e.clip = +t.clipDepth;
        if (t.placeFlagHasRatio === 'true') e.ratio = +t.ratio;
        if (t.placeFlagHasBlendMode === 'true') e.blend = +t.blendMode;
        if (t.placeFlagHasFilterList === 'true' && t.surfaceFilterList) {
          e.filters = [].concat(t.surfaceFilterList.item || []).map((f) => {
            const o = { t: f.type };
            for (const k of ['blurX', 'blurY', 'strength', 'passes', 'innerGlow', 'innerShadow', 'knockout', 'angle', 'distance']) if (f[k] !== undefined) o[k] = isNaN(+f[k]) ? f[k] : +f[k];
            const col = f.glowColor || f.dropShadowColor;
            if (col) o.color = [+col.red, +col.green, +col.blue, +col.alpha];
            if (f.matrix) o.matrix = [].concat(f.matrix.item || []).map(Number);
            return o;
          });
        }
        list.set(d, e);
        break;
      }
      case 'RemoveObjectTag':
      case 'RemoveObject2Tag':
        list.delete(+t.depth);
        break;
      case 'FrameLabelTag':
        labels[t.name] = frames.length;
        break;
      case 'ShowFrameTag':
        frames.push([...list.values()].sort((a, b) => a.d - b.d));
        break;
    }
  }
  return { n: frames.length, labels, frames };
}

for (const t of tags) {
  switch (t.type) {
    case 'SymbolClassTag': {
      const ids = [].concat(t.tags.item), names = [].concat(t.names.item);
      ids.forEach((id, i) => (out.symbols[id] = names[i]));
      break;
    }
    case 'DefineSpriteTag':
      out.sprites[t.spriteId] = simulateSprite(t.subTags && t.subTags.item);
      break;
    case 'DefineShapeTag': case 'DefineShape2Tag': case 'DefineShape3Tag': case 'DefineShape4Tag':
      out.shapes[t.shapeId] = rect(t.shapeBounds);
      break;
    case 'DefineMorphShapeTag': case 'DefineMorphShape2Tag':
      out.shapes[t.characterId] = rect(t.startBounds);
      break;
    case 'DefineBitsTag': case 'DefineBitsJPEG2Tag': case 'DefineBitsJPEG3Tag': case 'DefineBitsJPEG4Tag':
    case 'DefineBitsLosslessTag': case 'DefineBitsLossless2Tag':
      out.images[t.characterID ?? t.characterId] = { w: +t.bitmapWidth || null, h: +t.bitmapHeight || null, type: t.type };
      break;
    case 'DefineTextTag': case 'DefineText2Tag':
      // static text: rendered from FFDec SVG export (origin = textBounds min after textMatrix)
      out.texts[t.characterID ?? t.characterId] = { b: rect(t.textBounds), m: matrix(t.textMatrix) };
      break;
    case 'DefineEditTextTag': {
      const raw = t.initialText || '';
      const plain = raw.replace(/<br\s*\/?>/gi, '\n').replace(/<\/p>\s*<p[^>]*>/gi, '\n').replace(/<[^>]+>/g, '')
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ');
      const sz = raw.match(/size="(\d+)"/);
      const col = raw.match(/color="#([0-9a-fA-F]{6})"/);
      const al = raw.match(/align="(\w+)"/);
      const tc = t.textColor;
      out.edits[t.characterID ?? t.characterId] = {
        b: rect(t.bounds), text: plain,
        size: sz ? +sz[1] : (t.fontHeight ? +t.fontHeight / T : 12),
        color: col ? '#' + col[1] : (tc ? '#' + [tc.red, tc.green, tc.blue].map((v) => (+v).function toString() { [native code] }(16).padStart(2, '0')).join('') : '#000000'),
        align: al ? al[1] : ['left', 'right', 'center', 'justify'][+t.align || 0],
        multiline: t.multiline === 'true', wrap: t.wordWrap === 'true', var: t.variableName || '',
      };
      break;
    }
    case 'DefineButton2Tag': case 'DefineButtonTag': {
      const recs = [].concat((t.characters && t.characters.item) || []).filter((r) => r.type === 'BUTTONRECORD');
      const st = (r) => (r.buttonStateUp === 'true' ? 1 : 0) | (r.buttonStateOver === 'true' ? 2 : 0) | (r.buttonStateDown === 'true' ? 4 : 0) | (r.buttonStateHitTest === 'true' ? 8 : 0);
      out.buttons[t.buttonId] = recs.map((r) => {
        const e = [+r.placeDepth, +r.characterId, st(r), ...matrix(r.placeMatrix)];
        const ct = r.colorTransform;
        if (ct && (ct.hasMultTerms === 'true' || ct.hasAddTerms === 'true')) {
          const mu = (v) => (v === undefined ? 1 : +v / 256), ad = (v) => (v === undefined ? 0 : +v);
          e.push([mu(ct.redMultTerm), mu(ct.greenMultTerm), mu(ct.blueMultTerm), mu(ct.alphaMultTerm), ad(ct.redAddTerm), ad(ct.greenAddTerm), ad(ct.blueAddTerm), ad(ct.alphaAddTerm)]);
        }
        return e;
      }).sort((a, b) => a[0] - b[0]);
      break;
    }
  }
}
// main timeline
out.root = simulateSprite(tags);
fs.writeFileSync(outFile, JSON.stringify(out));
console.log('symbols', Object.keys(out.symbols).length, 'sprites', Object.keys(out.sprites).length, 'shapes', Object.keys(out.shapes).length, 'images', Object.keys(out.images).length, 'texts', Object.keys(out.texts).length, 'edits', Object.keys(out.edits).length, 'buttons', Object.keys(out.buttons).length);
