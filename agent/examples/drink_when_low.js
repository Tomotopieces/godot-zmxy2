// A guard to merge into another script: wake the agent once when HP falls under a share (params.share, default 0.35).
export default {
  hz: 5,
  onTick(obs, ctx) {
    const h = obs.hero
    if (!h || !h.hp_max) return {}
    const low = h.hp / h.hp_max < (ctx.params.share || 0.35)
    if (low && !ctx.memo.warned) { ctx.memo.warned = true; ctx.wake(`HP ${h.hp}/${h.hp_max}`) }
    if (!low) ctx.memo.warned = false
    return {}
  },
}
