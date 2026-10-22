// The agent's loop on the server side: the running script (observe -> onTick -> input, at the script's rate), the
// watchdog that decides when to wake the agent, and the log the next wait_events summarises.
import { ScriptBox, cleanInput } from "./sandbox.js";
import { sleep } from "./bridge.js";

export const WATCH_DEFAULTS = {
  hp_below: 0.3,          // hero HP share
  stuck_sec: 20,          // hero has not moved and the room has not changed for this long
  boss: true,             // a boss appears
  stage_end: true,        // stage cleared / failed, hero died
  drops: [],              // item names: wake when one of them drops
  heartbeat_sec: 30,      // the longest wait_events waits
  max_wakes_per_min: 6,
};

export class Runner {
  constructor(bridge, log) {
    this.bridge = bridge;
    this.log = log;
    this.watch = { ...WATCH_DEFAULTS };
    this.script = null;          // {box, name, params, memo, startedAt, ticks, lastInput}
    this.events = [];            // since the last wait_events
    this.wakes = [];             // pending wake reasons
    this.wakeTimes = [];
    this.waiters = new Set();
    this.lastObs = null;
    this.stuck = { x: null, room: null, since: Date.now() };
    this.hpLow = false;
    this.manualUntil = 0;        // act / sequence hold the controls: the script waits
    bridge.onEvent((ev) => this.#onGameEvent(ev));
  }

  // ------------------------------------------------------------ events and waking

  #onGameEvent(ev) {
    if (ev.ev === "hello") return;
    this.events.push({ ...ev, at: Date.now() });
    if (this.events.length > 400) this.events.splice(0, this.events.length - 400);
    const w = this.watch;
    switch (ev.ev) {
      case "boss_appear": if (w.boss) this.wake(`boss appeared: ${ev.name}`); break;
      case "stage_clear": if (w.stage_end) this.wake(`stage cleared: ${ev.stage}`); break;
      case "stage_fail": if (w.stage_end) this.wake(`stage failed: ${ev.stage}`); break;
      case "death": if (w.stage_end) this.wake("hero died"); break;
      case "drop": if (w.drops.includes(ev.name)) this.wake(`dropped: ${ev.name}`); break;
      case "disconnected": this.stopScript("game disconnected"); this.wake("game disconnected"); break;
      case "hurt":
        if (ev.hp_max > 0 && ev.hp / ev.hp_max < w.hp_below) {
          if (!this.hpLow) this.wake(`HP low: ${ev.hp}/${ev.hp_max}`);
          this.hpLow = true;
        }
        break;
    }
    if (this.script && ev.ev !== "disconnected") this.#scriptEvent(ev);
  }

  /** Ask for the agent's attention (merged and rate-limited; safety wakes always pass). */
  wake(reason, urgent = false) {
    const now = Date.now();
    this.wakeTimes = this.wakeTimes.filter((t) => now - t < 60000);
    if (!urgent && this.wakeTimes.length >= this.watch.max_wakes_per_min) {
      this.events.push({ ev: "wake_dropped", reason, at: now });
      return;
    }
    this.wakeTimes.push(now);
    this.wakes.push(reason);
    for (const fn of this.waiters) fn();
  }

  /** wait_events: until a wake or `seconds` pass; returns the summary of what happened. */
  async waitEvents(seconds) {
    const ms = Math.max(0.5, Math.min(seconds ?? this.watch.heartbeat_sec, 60)) * 1000;
    if (this.wakes.length === 0) {
      await new Promise((resolve) => {
        const done = () => { clearTimeout(t); this.waiters.delete(done); resolve(); };
        const t = setTimeout(done, ms);
        this.waiters.add(done);
      });
    }
    const wakes = this.wakes.splice(0);
    const events = this.events.splice(0);
    let obs = null;
    try { obs = await this.bridge.request("observe"); this.lastObs = obs; } catch { /* not connected */ }
    return { woke: wakes.length > 0, reasons: wakes, summary: summarise(events, obs, this.script), events: trimEvents(events),
      script: this.scriptStatus(), obs: obs && brief(obs) };
  }

  // ------------------------------------------------------------ the script

  scriptStatus() {
    const s = this.script;
    if (!s) return null;
    return { name: s.name, running_sec: Math.round((Date.now() - s.startedAt) / 1000), ticks: s.ticks, memo: s.memo };
  }

  async startScript(code, name, params) {
    const box = await ScriptBox.create(code);   // throws on syntax errors and a missing onTick
    this.stopScript("replaced");
    const s = { box, name: name || "script", params: params || {}, memo: {}, startedAt: Date.now(), ticks: 0,
      lastInput: { hold: [], press: [] }, logs: [], stop: false };
    this.script = s;
    this.#loop(s);
    return { name: s.name, hz: box.hz };
  }

  async updateScript(code, keepMemo) {
    const s = this.script;
    if (!s) throw new Error("no script running");
    const box = await ScriptBox.create(code);
    s.box.dispose();
    s.box = box;
    if (!keepMemo) s.memo = {};
    this.events.push({ ev: "log", text: "script updated", at: Date.now() });
    return { name: s.name, hz: box.hz };
  }

  stopScript(why = "stopped") {
    const s = this.script;
    if (!s) return false;
    s.stop = true;
    this.script = null;
    s.box.dispose();
    this.bridge.request("release_all").catch(() => {});
    this.events.push({ ev: "script_stopped", name: s.name, why, at: Date.now() });
    return true;
  }

  #hook(s, fn, arg) {
    const r = s.box.call(fn, arg, s.memo, s.params);
    if (r === null) return null;
    s.memo = r.memo ?? {};
    for (const l of r.out.logs) this.events.push({ ev: "log", text: l, at: Date.now() });
    for (const w of r.out.wakes) this.wake(`script: ${w}`);
    if (r.out.done) {
      this.events.push({ ev: "script_done", result: r.out.done.result, at: Date.now() });
      this.stopScript("done");
      this.wake(`script done: ${JSON.stringify(r.out.done.result).slice(0, 200)}`, true);
      return null;
    }
    return r.ret;
  }

  #scriptEvent(ev) {
    const s = this.script;
    try { this.#hook(s, "onEvent", ev); } catch (e) { this.#crash(s, e, null); }
  }

  #crash(s, e, obs) {
    if (this.script !== s) return;
    this.events.push({ ev: "script_error", error: e.message, stack: (e.stack || "").slice(0, 600), at: Date.now() });
    this.stopScript("error");
    this.wake(`script error: ${e.message}`, true);
    if (obs) this.lastObs = obs;
  }

  async #loop(s) {
    const period = () => 1000 / s.box.hz;
    let first = true;
    while (!s.stop) {
      const t0 = Date.now();
      if (Date.now() < this.manualUntil || !this.bridge.connected) {
        await sleep(100);
        continue;
      }
      let obs;
      try {
        obs = await this.bridge.request("observe");
      } catch {
        await sleep(300);
        continue;
      }
      if (s.stop) break;
      this.lastObs = obs;
      this.#watchStuck(obs);
      try {
        if (first) {
          first = false;
          this.#hook(s, "onStart", obs);
          if (s.stop) break;
        }
        const ret = this.#hook(s, "onTick", obs);
        if (s.stop) break;
        if (ret !== null) {
          const inp = cleanInput(ret);
          s.ticks++;
          if (inp.press.length || !sameHold(inp.hold, s.lastInput.hold)) {
            await this.bridge.request("input", inp);
          }
          s.lastInput = inp;
        }
      } catch (e) {
        this.#crash(s, e, obs);
        break;
      }
      const wait = period() - (Date.now() - t0);
      if (wait > 0) await sleep(wait);
    }
  }

  #watchStuck(obs) {
    if (obs.hero?.hp_max && obs.hero.hp / obs.hero.hp_max >= this.watch.hp_below) this.hpLow = false;
    if (obs.screen !== "stage" || !obs.hero || obs.paused) {
      this.stuck = { x: null, room: null, since: Date.now() };
      return;
    }
    const x = Math.round(obs.hero.x / 20), room = obs.stage?.room;
    if (x !== this.stuck.x || room !== this.stuck.room) {
      this.stuck = { x, room, since: Date.now(), woke: false };
      return;
    }
    if (!this.stuck.woke && Date.now() - this.stuck.since > this.watch.stuck_sec * 1000) {
      this.stuck.woke = true;
      this.wake(`stuck: no progress for ${this.watch.stuck_sec}s at x=${Math.round(obs.hero.x)}`);
    }
  }
}

const sameHold = (a, b) => a.length === b.length && a.every((x) => b.includes(x));

/** The observation without the bulky parts (floors), for summaries. */
export function brief(o) {
  const b = { screen: o.screen, paused: o.paused, souls: o.souls };
  if (o.hero) {
    const h = o.hero;
    b.hero = h.hp_max ? { hp: `${h.hp}/${h.hp_max}`, mp: `${h.mp}/${h.mp_max}`, level: h.level, x: h.x, y: h.y, state: h.state }
      : { level: h.level, role: h.role };
  }
  if (o.stage) b.stage = { id: o.stage.id, room: `${o.stage.room}/${o.stage.rooms}`, door_open: o.stage.door_open };
  if (o.enemies) b.enemies = o.enemies.length;
  if (o.pickups?.length) b.pickups = o.pickups.map((p) => p.name);
  return b;
}

function trimEvents(events) {
  const keep = events.filter((e) => !["hurt", "log", "kill", "notice", "drop", "pickup"].includes(e.ev)).slice(-30);
  return keep.map(({ at, ...e }) => e);
}

/** One line of what happened since the last wait. */
export function summarise(events, obs, script) {
  const c = (k) => events.filter((e) => e.ev === k);
  const kills = c("kill"), hurts = c("hurt"), picks = c("pickup"), logs = c("log"), notes = c("notice");
  const drops = c("drop"), gone = c("drop_expired");
  const item = (p) => `${p.name}(${[p.quality, p.type].filter(Boolean).join(" ")})`;
  const parts = [];
  if (obs?.stage) parts.push(`${obs.stage.id} room ${obs.stage.room}/${obs.stage.rooms}`);
  else if (obs) parts.push(obs.screen);
  if (kills.length) parts.push(`kills ${kills.length}` + (kills.some((k) => k.boss) ? ` (boss: ${kills.filter((k) => k.boss).map((k) => k.name).join(",")})` : ""));
  if (hurts.length) {
    const low = Math.min(...hurts.map((h) => h.hp / h.hp_max));
    parts.push(`hit ${hurts.length}x, -${hurts.reduce((s, h) => s + h.damage, 0)} HP, lowest ${Math.round(low * 100)}%`);
  }
  if (drops.length || picks.length || gone.length) parts.push(`drops ${drops.length}, picked ${picks.length}, vanished ${gone.length}`);
  if (picks.length) parts.push("picked " + picks.map(item).join(", "));
  if (gone.length) parts.push("VANISHED unpicked: " + gone.map(item).join(", "));
  if (notes.length) parts.push("notices: " + [...new Set(notes.map((n) => n.text))].slice(0, 5).join(" | "));
  if (logs.length) parts.push("script log: " + logs.slice(-8).map((l) => l.text).join(" | "));
  if (script) parts.push(`script ${script.name} running`);
  return parts.join(" · ");
}
