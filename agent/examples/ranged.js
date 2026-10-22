// Ranged heroes (唐僧): keep a distance from the nearest enemy, face it and shoot; step back when it comes close.
// params: { near: 140, far: 360 }
export default {
  hz: 15,
  onTick(obs, ctx) {
    if (obs.screen !== "stage" || !obs.hero || obs.paused) return {}
    const h = obs.hero
    const near = ctx.params.near || 140, far = ctx.params.far || 360
    const foes = (obs.enemies || []).filter((e) => e.hittable && Math.abs(e.y - h.y) < 160)
    if (!foes.length) {
      if (obs.stage.door_open) { ctx.done("room clear, door open"); return {} }
      return { hold: ["right"] }
    }
    foes.sort((a, b) => Math.abs(a.x - h.x) - Math.abs(b.x - h.x))
    const e = foes[0]
    const dir = e.x > h.x ? 1 : -1
    const dist = Math.abs(e.x - h.x)
    const toward = dir > 0 ? "right" : "left", away = dir > 0 ? "left" : "right"
    if (dist < near) return { hold: [away] }          // too close: back off (turns away; face again next tick)
    if (dist > far) return { hold: [toward] }
    if (h.facing !== dir) return { hold: [toward] }   // one tick of walking turns the hero
    return h.can_act ? { press: ["attack"] } : {}
  },
  onEvent(e, ctx) {
    if (e.ev === "whiff") ctx.memo.whiffs = (ctx.memo.whiffs || 0) + 1
  },
}
