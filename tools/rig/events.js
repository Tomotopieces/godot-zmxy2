// Gameplay events from body frame scripts.
// Each script becomes a list of [name, ...args]. Velocities are converted from px/frame to px/s.
//   finished                 action is over (original script switched curAction / removed the clip)
//   new_hit                  a new attack id: targets can be hit again (multi-hit moves)
//   stop_move                horizontal input state cleared
//   scale_vx k / scale_vy k  velocity *= k
//   set_vx v / set_vy v      velocity = v (px/s)
//   set_vx_forward v         velocity.x = v in facing direction (px/s, positive = forward)
//   grounded_call m          if on the floor: call m and hold the animation
//   call m args...           actor method (snake_case of the original method)
//   vis 0|1                  the owner is hidden / shown (becomes an animation track, not an event)
//   boss_dead_fx             the boss-death sequence starts (actor method)
//   shake px                 screen shake
//   unknown src              a script nobody has read yet: dropped, and reported by the extractor so it gets read
'use strict';

const OWNER = /(?:[A-Za-z0-9_]+\((?:this\.parent(?:\.parent)?)\)|this\.parent(?:\.parent)?)/g;
const IGNORED_CALLS = new Set(['newAttackId', 'setStatic', 'isInSky', 'isStatic', 'isAttacking', 'gotoAndStop', 'gotoAndPlay', 'removeChild', 'isRunning']);

const snake = (n) => n.replace(/([a-z0-9])([A-Z])/g, '$1_$2').replace(/([A-Z])([A-Z][a-z])/g, '$1_$2').toLowerCase();

function classifyEvents(src, fps) {
  let s = src.replace(OWNER, 'P').replace(/Boolean\(P\) && /g, '');
  // "if (facing) vx = A else vx = B" -> the conditional form handled below (a > 0 = art not mirrored = facing left)
  s = s.replace(/if\(P\.transform\.matrix\.a ([<>]) 0\) \{ P\.speed\.(x|y) = (-?[\d.]+); \} else \{ P\.speed\.\2 = (-?[\d.]+); \}/g,
    (_, op, ax, a, b) => `P.speed.${ax} = P.transform.matrix.a == -1 ? ${op === '>' ? b : a} : ${op === '>' ? a : b};`);
  const out = [];
  if (/^(stop\(\);\s*)+$/.test(s)) return out;

  // purposes: scripts are not translated line by line; each one is read for what it is for and matched by that
  // hide / show the whole body (death blink, a move that leaves the screen)
  const vis = s.match(/^(?:trace\("[^"]*"\); )*if\(P\) \{ (?:trace\("[^"]*"\); )?P\.visible = (true|false); \}$/);
  if (vis) return [['vis', vis[1] === 'true' ? 1 : 0]];
  // the original re-dresses the body with the worn equipment; EquipSlot nodes follow the equipment by themselves
  // (unless the script also fires something: the charge shot's frame re-dresses the body and then shoots)
  if ((/P\.setEquips\(/.test(s) || /bodyEquip\.numChildren/.test(s)) && !/P\.do[A-Z]\w*\(/.test(s)) return out;
  // the full-screen boss death sequence
  if (/BossDead/.test(s)) return [['boss_dead_fx']];
  // screen shake
  const shake = s.match(/vControllor\.shake\((\d+)\)/);
  if (shake) return [['shake', +shake[1]]];
  // done by the actor's own code: the dash speed of a hero / monster move, loops and holds inside effect clips
  if (/^if\(P\) \{ P\.speed\.x = P\.transform\.matrix\.a < 0 \? 30 : -30; \}$/.test(s) || /this\.speed = P\.isGXP/.test(s)
      || /^this\.gotoAndPlay\(\d+\);$/.test(s) || /^this\.gotoAndStop\(this\.totalFrames\);$/.test(s)) return out;

  const grounded = s.match(/^if\(P\.standInObj\) \{ P\.(\w+)\(\); this\.stop\(\); \}$/);
  if (grounded) return [['grounded_call', snake(grounded[1])]];

  // velocity writes, in source order
  const re = /P\.speed\.(x|y) = (?:P\.speed\.(?:x|y) \* (-?[\d.]+)|P\.transform\.matrix\.a == (-?1) \? (-?[\d.]+) : (-?[\d.]+)|(-?[\d.]+))/g;
  let m;
  while ((m = re.exec(s))) {
    const ax = m[1];
    if (m[2] !== undefined) out.push(['scale_v' + ax, +m[2]]);
    // matrix.a == -1 means facing right (art faces left). forward value = value used when facing right.
    else if (m[3] !== undefined) { const right = m[3] === '-1' ? +m[4] : +m[5]; out.push(['set_v' + ax + '_forward', right * fps]); }
    else out.push(['set_v' + ax, +m[6] * fps]);
  }
  if (/P\.newAttackId\(\)/.test(s)) out.push(['new_hit']);
  for (const c of s.matchAll(/P\.(\w+)\(([^()]*)\)/g)) {
    if (IGNORED_CALLS.has(c[1])) continue;
    const args = c[2].trim() ? c[2].split(',').map((x) => (isNaN(+x) ? x.trim() : +x)) : [];
    out.push(['call', snake(c[1]), ...args]);
  }
  const finished = /P\.curAction = |P\.gotoAndStop\("|removeChild\(this\)|P\.destroy\(\)/.test(s);
  if (/P\.setStatic\(\)/.test(s)) out.push(['stop_move']);
  if (finished) out.push(['finished']);
  if (!out.length) out.push(['unknown', s.slice(0, 200)]);
  return out;
}

module.exports = { classifyEvents, snake };
