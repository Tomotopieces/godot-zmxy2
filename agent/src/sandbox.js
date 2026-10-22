// The script sandbox: one agent script at a time, in QuickJS (no files, network, timers or game internals).
// A script is `export default { hz?, onStart?(obs, ctx), onTick(obs, ctx) -> {hold?, press?}, onEvent?(e, ctx) }`.
import { getQuickJS, shouldInterruptAfterDeadline } from "quickjs-emscripten";

const TICK_BUDGET_MS = 20;
const MAX_OVERRUNS = 10;
const MEMORY = 32 << 20;
export const ACTIONS = ["left", "right", "up", "down", "attack", "jump", "skill_u", "skill_i", "skill_o", "skill_l",
  "rage", "treasure", "run"];

let quickjs = null;
async function qjs() {
  if (!quickjs) quickjs = await getQuickJS();
  return quickjs;
}

// The script's module text becomes a plain script: `export default X` -> `globalThis.__script = X`.
function toScript(code) {
  const out = code.replace(/^\s*export\s+default\s+/m, "globalThis.__script = ");
  if (out === code) throw new Error("the script must `export default { onTick(obs, ctx) { ... } }`");
  return out;
}

// What the script sees as `ctx`: memo and params are plain data kept on the host side and copied in each call; the
// functions queue requests that the host reads back after the call.
const PRELUDE = `
globalThis.__out = { logs: [], wakes: [], done: null };
globalThis.__ctx = {
  memo: {}, params: {},
  log(t) { __out.logs.push(String(t).slice(0, 300)); },
  wake(r) { __out.wakes.push(String(r).slice(0, 300)); },
  done(r) { __out.done = { result: r === undefined ? null : r }; },
};
globalThis.console = { log: (...a) => __ctx.log(a.map(String).join(" ")) };
globalThis.__call = function (fn, arg, memo, params) {
  __out = { logs: [], wakes: [], done: null };
  __ctx.memo = memo; __ctx.params = params;
  const f = __script && __script[fn];
  const ret = typeof f === "function" ? f.call(__script, arg, __ctx) : undefined;
  return JSON.stringify({ ret: ret === undefined ? null : ret, memo: __ctx.memo, out: __out });
};
`;

export class ScriptBox {
  static async create(code) {
    const Q = await qjs();
    const rt = Q.newRuntime();
    rt.setMemoryLimit(MEMORY);
    rt.setMaxStackSize(1 << 20);
    const vm = rt.newContext();
    const box = new ScriptBox(rt, vm);
    box.#evalOrThrow(PRELUDE, "prelude.js");
    box.#evalOrThrow(toScript(code), "script.js", 200);
    const info = box.#evalOrThrow(
      "JSON.stringify({ok: typeof __script === 'object' && __script !== null && typeof __script.onTick === 'function', hz: __script && __script.hz})",
      "check.js");
    const { ok, hz } = JSON.parse(info);
    if (!ok) {
      box.dispose();
      throw new Error("the default export needs an onTick(obs, ctx) function");
    }
    box.hz = Math.max(1, Math.min(30, Number(hz) || 20));
    return box;
  }

  constructor(rt, vm) {
    this.rt = rt;
    this.vm = vm;
    this.overruns = 0;
  }

  #evalOrThrow(code, name, budget = TICK_BUDGET_MS) {
    this.rt.setInterruptHandler(shouldInterruptAfterDeadline(Date.now() + budget));
    const r = this.vm.evalCode(code, name);
    if (r.error) {
      const e = this.vm.dump(r.error);
      r.error.dispose();
      const err = new Error(typeof e === "object" ? `${e.name}: ${e.message}` : String(e));
      err.stack = typeof e === "object" ? e.stack : "";
      err.interrupted = typeof e === "object" && e.message === "interrupted";
      throw err;
    }
    const v = this.vm.dump(r.value);
    r.value.dispose();
    return v;
  }

  /** Call one of the script's hooks. Returns {ret, memo, out} or throws; a hook over its time budget returns null. */
  call(fn, arg, memo, params) {
    const code = `__call(${JSON.stringify(fn)}, ${JSON.stringify(arg)}, ${JSON.stringify(memo)}, ${JSON.stringify(params)})`;
    try {
      const r = JSON.parse(this.#evalOrThrow(code, fn + ".js"));
      this.overruns = 0;
      return r;
    } catch (e) {
      if (e.interrupted) {
        this.overruns++;
        if (this.overruns >= MAX_OVERRUNS) throw new Error(`${fn} ran over ${TICK_BUDGET_MS} ms ${MAX_OVERRUNS} times in a row`);
        return null;
      }
      throw e;
    }
  }

  dispose() {
    try { this.vm.dispose(); } catch { /* already gone */ }
    try { this.rt.dispose(); } catch { /* already gone */ }
  }
}

/** The input a hook returned, cleaned: only known actions. */
export function cleanInput(ret) {
  if (!ret || typeof ret !== "object") return { hold: [], press: [] };
  const pick = (a) => (Array.isArray(a) ? a.filter((x) => ACTIONS.includes(x)) : []);
  return { hold: pick(ret.hold), press: pick(ret.press) };
}
