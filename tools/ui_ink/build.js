// Ink-brush UI kit generator. The pictures are made from parameters: SVG shapes pushed through SVG filters (turbulence
// noise displaces the edges into torn brush edges, anisotropic noise cuts dry-brush hair, blur + threshold makes ink
// bleed), rendered by headless Chrome with a transparent background, and written as PNGs (2x) with a manifest of the
// 9-slice margins. Nothing here is drawn by hand: change a number, run again.
//
//   node tools/ui_ink/build.js [out dir]      default game/assets/ui_ink
//
// Needs Chrome or Edge (CHROME env var, or the usual install paths). No npm packages.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const OUT = path.resolve(process.argv[2] || path.join(__dirname, '..', '..', 'game', 'assets', 'ui_ink'));
const SCALE = 2;
const INK = '#14101a';
const GOLD = '#e8b84a';

function chrome() {
  const c = [process.env.CHROME, 'C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe', '/usr/bin/google-chrome', '/usr/bin/chromium'];
  for (const p of c) if (p && fs.existsSync(p)) return p;
  throw new Error('no Chrome / Edge found (set CHROME)');
}

// --- filters -----------------------------------------------------------------------------------------------------

// A torn brush edge: the shape's outline wanders with low-frequency noise (`tear`) and frays with finer noise (`fray`).
function tear(id, seed, tear = 9, fray = 3) {
  return `<filter id="${id}" x="-12%" y="-12%" width="124%" height="124%" color-interpolation-filters="sRGB">
  <feTurbulence type="fractalNoise" baseFrequency="0.028 0.034" numOctaves="3" seed="${seed}" result="n1"/>
  <feDisplacementMap in="SourceGraphic" in2="n1" scale="${tear}" xChannelSelector="R" yChannelSelector="G" result="d1"/>
  <feTurbulence type="fractalNoise" baseFrequency="0.22 0.3" numOctaves="2" seed="${seed + 11}" result="n2"/>
  <feDisplacementMap in="d1" in2="n2" scale="${fray}" xChannelSelector="G" yChannelSelector="R"/>
</filter>`;
}

// Dry-brush: hairline streaks (noise stretched along x) eat into what is drawn.
function dry(id, seed, amount = 1.0, freq = '0.012 0.9') {
  return `<filter id="${id}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
  <feTurbulence type="fractalNoise" baseFrequency="${freq}" numOctaves="3" seed="${seed}" result="h"/>
  <feColorMatrix in="h" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 ${(-3.4 * amount).toFixed(2)} ${(2.35 * amount + (1 - amount)).toFixed(2)}" result="a"/>
  <feComposite in="SourceGraphic" in2="a" operator="in"/>
</filter>`;
}

// Paper / ink mottling: soft blotches of lighter and darker ink inside a shape.
function mottle(id, seed, strength = 0.35) {
  return `<filter id="${id}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
  <feTurbulence type="fractalNoise" baseFrequency="0.018 0.03" numOctaves="4" seed="${seed}" result="n"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  ${strength} 0 0 0 ${-strength * 0.42}" result="w"/>
  <feComposite in="w" in2="SourceAlpha" operator="in"/>
</filter>`;
}

// --- shapes ------------------------------------------------------------------------------------------------------

function rrect(x, y, w, h, r, extra = '') {
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" ry="${r}" ${extra}/>`;
}

// ink splatters: small round drops scattered around a box (deterministic)
function splatter(seed, boxes, color = INK) {
  let s = seed;
  const rnd = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
  const out = [];
  for (const b of boxes) {
    for (let i = 0; i < b.n; i++) {
      const r = 0.8 + rnd() * rnd() * b.r;
      out.push(`<circle cx="${(b.x + rnd() * b.w).toFixed(1)}" cy="${(b.y + rnd() * b.h).toFixed(1)}" r="${r.toFixed(1)}" fill="${color}"/>`);
    }
  }
  return out.join('');
}

// --- assets ------------------------------------------------------------------------------------------------------
// each: { name, w, h (1x px), margin (9-slice, 1x px), svg(): string }

const assets = [];

assets.push({
  name: 'panel', w: 360, h: 260, margin: 46,
  svg: () => `
  <defs>${tear('t', 4, 12, 4)}${tear('t2', 9, 3, 1.5)}${mottle('m', 21, 0.32)}${dry('dr', 5, 0.5)}</defs>
  <g filter="url(#t)">${rrect(20, 20, 320, 220, 14, `fill="${INK}" fill-opacity="0.95"`)}</g>
  <g filter="url(#m)" opacity="0.5">${rrect(28, 28, 304, 204, 10, 'fill="#fff"')}</g>
  <g filter="url(#t2)">${rrect(32, 32, 296, 196, 8, `fill="none" stroke="${GOLD}" stroke-width="1.6" stroke-opacity="0.85"`)}</g>
  <g filter="url(#dr)">${rrect(26, 26, 308, 208, 12, 'fill="none" stroke="#fff" stroke-width="2.4" stroke-opacity="0.35"')}</g>
  ${splatter(7, [{ x: 4, y: 4, w: 40, h: 40, n: 7, r: 4 }, { x: 316, y: 214, w: 40, h: 40, n: 8, r: 4.5 }, { x: 330, y: 6, w: 24, h: 24, n: 4, r: 3 }])}`,
});

assets.push({
  name: 'tooltip', w: 280, h: 200, margin: 30,
  svg: () => `
  <defs>${tear('t', 12, 7, 2.5)}${tear('t2', 3, 2, 1)}${mottle('m', 6, 0.3)}</defs>
  <g filter="url(#t)">${rrect(12, 12, 256, 176, 10, `fill="#0e0b13" fill-opacity="0.93"`)}</g>
  <g filter="url(#m)" opacity="0.5">${rrect(16, 16, 248, 168, 8, 'fill="#fff"')}</g>
  <g filter="url(#t2)">${rrect(20, 20, 240, 160, 6, `fill="none" stroke="${GOLD}" stroke-width="1.4" stroke-opacity="0.8"`)}</g>
  ${splatter(3, [{ x: 2, y: 2, w: 24, h: 24, n: 4, r: 3 }, { x: 252, y: 172, w: 24, h: 24, n: 4, r: 3 }])}`,
});

function button(name, top, bottom, edge, shine, text) {
  assets.push({
    name, w: 168, h: 52, margin: 20,
    svg: () => `
  <defs>${tear('t', 31, 4, 2)}${dry('dr', 8, 0.55, '0.01 0.7')}
   <linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${top}"/><stop offset="1" stop-color="${bottom}"/></linearGradient></defs>
  <g filter="url(#t)">${rrect(8, 8, 152, 36, 12, `fill="${edge}"`)}</g>
  <g filter="url(#t)">${rrect(11, 11, 146, 30, 10, 'fill="url(#g)"')}</g>
  <g filter="url(#dr)">${rrect(14, 13, 140, 13, 7, `fill="${shine}" fill-opacity="0.5"`)}</g>
  ${text ? '' : ''}`,
  });
}
button('btn', '#f4cf6a', '#cf942a', INK, '#fff4c8');
button('btn_hover', '#ffe08a', '#e0a636', INK, '#ffffff');
button('btn_down', '#c8902a', '#a8701c', INK, '#e8c070');
button('btn_off', '#6a6672', '#4c4852', '#241f2a', '#9a96a0');

assets.push({
  name: 'hud_plate', w: 290, h: 96, margin: 30,
  svg: () => `
  <defs>${tear('t', 17, 8, 4)}${dry('dr', 2, 0.6, '0.008 0.8')}${tear('t2', 5, 2, 1)}${mottle('m', 14, 0.4)}</defs>
  <g filter="url(#t)">
    <path d="M18 24 Q140 8 272 20 L276 70 Q150 86 16 74 Z" fill="${INK}" fill-opacity="0.94"/>
  </g>
  <g filter="url(#m)" opacity="0.45"><path d="M24 28 Q140 14 266 24 L270 66 Q150 80 22 70 Z" fill="#fff"/></g>
  <g filter="url(#dr)"><path d="M16 74 Q150 88 276 70" fill="none" stroke="#fff" stroke-width="3.5" stroke-opacity="0.5"/></g>
  <g filter="url(#t2)"><path d="M26 30 Q140 18 264 28" fill="none" stroke="${GOLD}" stroke-width="1.3" stroke-opacity="0.7"/></g>
  ${splatter(11, [{ x: 262, y: 6, w: 26, h: 26, n: 8, r: 3.4 }, { x: 2, y: 60, w: 26, h: 30, n: 6, r: 3 }])}`,
});

assets.push({
  name: 'bar_frame', w: 180, h: 28, margin: 12,
  svg: () => `
  <defs>${tear('t', 40, 3, 1.4)}${dry('dr', 4, 0.5, '0.01 0.9')}</defs>
  <g filter="url(#t)">${rrect(6, 6, 168, 16, 8, `fill="${INK}"`)}</g>
  <g filter="url(#dr)">${rrect(8, 7, 164, 3, 1.5, 'fill="#fff" fill-opacity="0.35"')}</g>`,
});

function barFill(name, a, b, c) {
  assets.push({
    name, w: 168, h: 16, margin: 0,
    svg: () => `
  <defs>${tear('t', 23, 2, 1.2)}${dry('dr', 9, 0.55, '0.01 0.85')}
   <linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="0.55" stop-color="${b}"/><stop offset="1" stop-color="${c}"/></linearGradient></defs>
  <g filter="url(#t)">${rrect(2, 2, 164, 12, 6, 'fill="url(#g)"')}</g>
  <g filter="url(#dr)">${rrect(4, 3, 160, 4, 2, 'fill="#fff" fill-opacity="0.55"')}</g>`,
  });
}
barFill('bar_hp', '#ff7a66', '#e02a1c', '#8a0e0e');
barFill('bar_mp', '#7ab8ff', '#2a6ae0', '#10358a');
barFill('bar_exp', '#f2f0e0', '#c8c4a8', '#8a8670');

assets.push({
  name: 'title_stroke', w: 300, h: 48, margin: 24,
  svg: () => `
  <defs>${tear('t', 51, 6, 3)}${dry('dr', 13, 0.7, '0.006 0.9')}</defs>
  <g filter="url(#t)"><path d="M10 28 Q80 12 150 24 T290 20 L288 34 Q220 40 150 34 T12 38 Z" fill="${INK}"/></g>
  <g filter="url(#dr)"><path d="M14 36 Q150 30 286 32" fill="none" stroke="#fff" stroke-width="3" stroke-opacity="0.45"/></g>`,
});

// --- render ------------------------------------------------------------------------------------------------------

function render() {
  fs.mkdirSync(OUT, { recursive: true });
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ink-'));
  const exe = chrome();
  const manifest = {};
  for (const a of assets) {
    const html = path.join(tmp, a.name + '.html');
    fs.writeFileSync(html, `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent;overflow:hidden}svg{display:block}</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="${a.w}" height="${a.h}" viewBox="0 0 ${a.w} ${a.h}">${a.svg()}</svg></body></html>`);
    const png = path.join(OUT, a.name + '.png');
    execFileSync(exe, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000', `--force-device-scale-factor=${SCALE}`,
      `--window-size=${a.w},${a.h}`, `--screenshot=${png}`, 'file:///' + html.replace(/\\/g, '/')], { stdio: 'pipe', timeout: 60000 });
    manifest[a.name] = { size: [a.w * SCALE, a.h * SCALE], margin: a.margin * SCALE, scale: SCALE };
    console.log('wrote', path.relative(process.cwd(), png));
  }
  fs.writeFileSync(path.join(OUT, 'ink.json'), JSON.stringify(manifest, null, 1));
  fs.rmSync(tmp, { recursive: true, force: true });
}

render();
