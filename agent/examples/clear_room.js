// Melee: walk on, face and hit the nearest enemy, jump over hostile shots, pick up drops, stop when the exit opens.
export default {
  hz: 15,
  onTick(obs, ctx) {
    if (obs.screen !== "stage" || !obs.hero || obs.paused) return {}
    const h = obs.hero
    if (h.state === "dead") return {}
    const reach = ctx.params.reach || 110
    const foes = (obs.enemies || []).filter((e) => e.hittable)
    // a hostile shot close in front: jump
    const shot = (obs.shots || []).find((s) => s.hostile && Math.abs(s.x - h.x) < 120 && Math.abs(s.y - (h.y - 60)) < 70)
    if (shot && h.on_floor) return { press: ["jump"] }
    if (foes.length) {
      foes.sort((a, b) => Math.abs(a.x - h.x) - Math.abs(b.x - h.x))
      const e = foes[0]
      const cx = e.box[0] + e.box[2] / 2
      const dir = cx > h.x ? 1 : -1
      const dist = Math.abs(cx - h.x) - e.box[2] / 2
      const side = dir > 0 ? "right" : "left"
      if (dist > reach) return { hold: [side] }
      if (h.facing !== dir) return { hold: [side] }
      return h.can_act ? { press: ["attack"] } : {}
    }
    // nothing to fight: drops first, then the way on
    const drop = (obs.pickups || []).find((p) => Math.abs(p.x - h.x) < 600)
    if (drop) return Math.abs(drop.x - h.x) < 10 ? {} : { hold: [drop.x > h.x ? "right" : "left"] }
    const st = obs.stage
    if (st.door_open) {
      if (st.door_x !== undefined && Math.abs(st.door_x - h.x) > 15) return { hold: [st.door_x > h.x ? "right" : "left"] }
      ctx.done("at the exit door")
      return {}
    }
    return { hold: ["right"] }
  },
}
