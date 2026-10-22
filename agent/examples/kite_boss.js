// Boss fight for melee heroes: close in and hit while the boss is not attacking; back off while it is; use skill_o
// (an invincible charge for 八戒) when it is ready and the boss is in front. params: { skill: "skill_o" }
export default {
  hz: 20,
  onTick(obs, ctx) {
    if (obs.screen !== "stage" || !obs.hero) return {}
    const h = obs.hero
    const boss = (obs.enemies || []).find((e) => e.boss && e.hittable) || (obs.enemies || []).find((e) => e.hittable)
    if (!boss) return {}
    const cx = boss.box[0] + boss.box[2] / 2
    const dir = cx > h.x ? 1 : -1
    const dist = Math.abs(cx - h.x) - boss.box[2] / 2
    const side = dir > 0 ? "right" : "left", away = dir > 0 ? "left" : "right"
    const attacking = /^hit/.test(boss.action)
    if (attacking && dist < 180 && !h.invincible) return { hold: [away] }
    const skill = ctx.params.skill || "skill_o"
    const sk = Object.values(h.skills || {}).find((s) => s.usable)
    if (h.can_act && dist < 260 && h.facing === dir && sk && !ctx.memo.cool) {
      ctx.memo.cool = 30
      return { press: [skill] }
    }
    if (ctx.memo.cool) ctx.memo.cool--
    if (dist > 100 || h.facing !== dir) return { hold: [side] }
    return h.can_act ? { press: ["attack"] } : {}
  },
}
