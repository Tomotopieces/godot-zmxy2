# Script API

A script is a JavaScript module whose default export has hooks. It runs in a sandbox on the MCP server (QuickJS: no
files, network, timers, `require` or game internals). The server calls `onTick` about `hz` times a second with the
current state and sends the keys it returns to the game. The game keeps running in real time between ticks.

```js
// A minimal script: walk right, attack anything close in front, stop when the room is clear.
export default {
  hz: 15,                                   // calls per second, 1..30 (default 20)
  onStart(obs, ctx) { ctx.log("start at " + obs.hero.x) },
  onTick(obs, ctx) {
    const h = obs.hero, foes = obs.enemies || []
    if (obs.screen !== "stage") return {}               // nothing to do outside a stage
    const near = foes.filter(e => e.hittable && Math.abs(e.x - h.x) < 120 && Math.abs(e.y - h.y) < 100)
    if (near.length) {
      const e = near[0]
      const face = e.x > h.x ? "right" : "left"
      return h.facing === (e.x > h.x ? 1 : -1) ? { press: ["attack"] } : { hold: [face] }
    }
    if (obs.stage.door_open) { ctx.done("door open"); return {} }
    return { hold: ["right"] }
  },
  onEvent(e, ctx) { if (e.ev === "kill") ctx.memo.kills = (ctx.memo.kills || 0) + 1 },
}
```

## Hooks

| hook | when | returns |
|---|---|---|
| `onStart(obs, ctx)` | once, before the first tick | — |
| `onTick(obs, ctx)` | `hz` times a second | `{ hold?: Action[], press?: Action[] }` |
| `onEvent(e, ctx)` | for each game event (see below) | — |

- `hold`: keys kept down until a later tick no longer lists them. Return the full set every tick.
- `press`: keys tapped once (down for two physics frames). Tapping a held key releases it for a frame first.
- Returning nothing (or `{}`) releases every held key.
- Each call has 20 ms; a call over it counts as no input; 10 in a row stop the script. An exception stops the script,
  releases every key and wakes the agent with the error and its stack.

## ctx

| | |
|---|---|
| `ctx.memo` | the script's own data, kept between calls (plain JSON). `script_update` keeps it unless told otherwise. |
| `ctx.params` | the `params` given to `script_run` |
| `ctx.log(text)` | a line in the log that `wait_events` summarises (`console.log` too) |
| `ctx.wake(reason)` | wake the agent (the script keeps running) |
| `ctx.done(result)` | stop the script and wake the agent with `result` |

## Actions

`left right up down attack jump skill_u skill_i skill_o skill_l rage treasure run`

- Keyboard equivalents: A/D move, W up (enter doors, W+J move), S down, J attack, K jump, U/I/O/L skills, Space rage
  (无双, when the rage bar is full), H the worn 法宝's skill. `run` holds the run modifier (or tap a direction twice).
- Drop through a platform: hold `down` and press `jump`. Double jump: press `jump` again in the air.
- Each hero's skills: resource zmxy2://docs/game.

## The state (`obs`)

Only what the screen shows. World pixels: x to the right, y down (the floor is around y 450..530). The screen is
940 x 590; `stage.view_x` is the left edge of the view.

```ts
{
  t, screen: "title"|"select_role"|"map"|"stage"|"result"|"menu"|"dialog"|"cartoon"|"loading", speed, paused, souls, merit,
  hero: { role, x, y, vx, vy, facing: -1|1, on_floor, state: "move"|"attack"|"hurt"|"dead", action,
          hp, hp_max, mp, mp_max, rage, rage_max, transformed, invincible, can_act, level, exp, exp_next,
          stats: { 生命上限, 魔法上限, 攻击, 防御, 暴击, 闪避, 回血, 回魔 },
          skills: { <key>: { name, learned, mp_cost, usable } }, buffs, debuffs, treasure },
  enemies: [{ uid, name, id, boss, x, y, box: [x, y, w, h], facing, hp /*0..1*/, action, hittable }],
  props:   [{ uid, name, id, x, y }],            // things to hit that are not enemies (10-1's dial and stones)
  shots:   [{ x, y, vx, vy, hostile }],
  pickups: [{ kind: "item"|"potion", name, quality?, type?, x, y, expires_in? }],   // type e.g. "八戒武器", "防具", "道具"; expires_in = seconds left (absent: stays, boss loot)
  stage:   { id: "2-1", view_x, view_w, width, room, rooms, locked, door_open, door_x?, floors: [{ x1, x2, y, h, oneway }] }
}
```

- `hero.x, y` is the feet. `enemies[].box` is the hurt box (where hits land); `x, y` its origin (usually the feet).
- `stage.room` counts the camera stops cleared; while `locked` the screen does not scroll on until the room's enemies
  are all gone. When `door_open`, walk into the door (`door_x`) and press `up` to finish the stage.
- `hero.can_act`: a new move can start now. `action` names the animation (`hit1`… attacks, `hurt`, `walk`, `wait`).
- Outside a stage only `t, screen, souls, merit, hero.{role, level}` are filled.

## Events (`onEvent`, and in `wait_events`)

`stage_start {stage}` · `hurt {damage, hp, hp_max}` · `kill {name, boss}` · `boss_appear {name}` · `room_clear {room}` ·
`drop {name, quality, type, x, y, expires_in}` · `pickup {name, quality, type}` · `pickup_blocked {name, quality, type, reason}` (touched but not taken: "背包已满（装备页 25/25）" -
sell or drop something; or "已拥有（只能有一件）"; reported once per touch, and a full bag wakes the agent) ·
`drop_expired {name, quality, type}` (it vanished
unpicked: dropped equipment lasts about 10 s, boss loot stays) · `stage_clear {stage, ending?}` · `stage_fail` · `death` ·
`level_up {level}` · `notice {text}` (the yellow on-screen notices, e.g. "背包已满")

## Tips

- Keep state in `ctx.memo` (where you were, what you tried); plain objects only.
- Face before attacking: a hero only hits forward. Melee reach is about 100 px for 八戒 / 悟空's combo.
- Back off when `shots` with `hostile` come close, or jump over them.
- Pick up drops by walking over them (`pickups`); most vanish after about 10 s (`expires_in`), so grab them between
  fights rather than after the room. wait_events lists what vanished unpicked. The bag has 25 cells per page.
- Prefer one script per kind of job (clear a room, fight a boss, collect drops) and switch with script_run.
