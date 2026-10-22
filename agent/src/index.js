#!/usr/bin/env node
// zmxy2-remake-mcp: lets any MCP-capable agent play 造梦西游2 重制版. Stdio MCP server; the game connects to it over a
// local WebSocket (see README.md). Logs go to stderr (stdout is the MCP channel).
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { GameBridge, sleep } from "./bridge.js";
import { Runner, WATCH_DEFAULTS, brief } from "./runner.js";
import { ScriptBox, cleanInput, ACTIONS } from "./sandbox.js";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const STATE = process.env.ZMXY2_STATE_DIR || join(ROOT, "state");
const SCRIPTS = join(STATE, "scripts");
const GOALS = join(STATE, "goals.json");
const PORT = Number(process.env.ZMXY2_PORT || 47823);
const log = (m) => process.stderr.write(`[zmxy2-mcp] ${m}\n`);

const bridge = new GameBridge({ port: PORT, stateDir: STATE, log });
bridge.start();
const runner = new Runner(bridge, log);

const server = new McpServer({ name: "zmxy2-remake", version: "0.1.0" }, {
  instructions: readFileSync(join(ROOT, "docs", "instructions.md"), "utf8"),
});

// ---------------------------------------------------------------- helpers

const text = (v) => ({ content: [{ type: "text", text: typeof v === "string" ? v : JSON.stringify(v) }] });
const fail = (e) => ({ isError: true, content: [{ type: "text", text: String(e?.message ?? e) }] });
const tool = (name, description, inputSchema, fn) =>
  server.registerTool(name, { description, inputSchema }, async (args) => {
    try { return await fn(args ?? {}); } catch (e) { return fail(e); }
  });
const actionList = z.array(z.enum(ACTIONS)).default([]);

function pick(o, fields) {
  if (!fields?.length) return o;
  const out = {};
  for (const f of fields) if (f in o) out[f] = o[f];
  return out;
}

// ---------------------------------------------------------------- connection

tool("connect_info", "How to connect the game: the connection string, whether the game is connected, its version.", {}, async () =>
  text({ url: bridge.url, connected: bridge.connected, game: bridge.hello,
    how: [`exe: start it with the argument --agent=${bridge.url} (or use launch_game)`,
      `web: open the game with ?agent=${encodeURIComponent(bridge.url)} added to its address`,
      "or paste the connection string in the game's 设置 -> AI 接入"] }));

tool("launch_game", "Start the game exe with the connection string and wait until it connects.",
  { exe: z.string().describe("path of the game's .exe"), wait_sec: z.number().min(1).max(120).default(30) },
  async ({ exe, wait_sec }) => {
    if (!existsSync(exe)) throw new Error("no such file: " + exe);
    const p = spawn(exe, [`--agent=${bridge.url}`], { detached: true, stdio: "ignore" });
    p.unref();
    const ok = await bridge.waitConnected(wait_sec * 1000);
    return text({ started: true, connected: ok, game: bridge.hello });
  });

// ---------------------------------------------------------------- observe

tool("get_state", "What is on the screen: screen name, hero, enemies (hp = health bar share), shots, pickups, stage " +
  "(rooms, exit door, floors in view). Coordinates are world pixels, x right, y down.",
  { fields: z.array(z.string()).optional().describe("only these top-level fields, e.g. [\"hero\",\"enemies\"]") },
  async ({ fields }) => text(pick(await bridge.request("observe"), fields)));

tool("get_screenshot", "A picture of the game window (for models that read images).",
  { scale: z.number().min(0.2).max(1).default(0.5) },
  async ({ scale }) => {
    const r = await bridge.request("screenshot", { scale });
    return { content: [{ type: "image", data: r.png, mimeType: "image/png" }] };
  });

// ---------------------------------------------------------------- UI

tool("list_ui", "The controls that can be pressed on the screen in front (menus, map, bag cells, dialogs).", {},
  async () => text(await bridge.request("ui_list")));

tool("press_ui", "Press a control of the screen in front by its id (from list_ui) or its exact text. Done the gamepad's " +
  "way: focus it, then A. On a comic page any id turns the page.",
  { id: z.string() },
  async ({ id }) => {
    const before = runner.events.length;
    const r = await bridge.request("ui_press", { target: id });
    await sleep(250);
    const notices = runner.events.slice(before).filter((e) => e.ev === "notice").map((e) => e.text);
    return text({ ...r, ...(notices.length ? { notices } : {}), ui: await bridge.request("ui_list") });
  });

tool("back_ui", "Back out of the screen in front, as B / Esc does: closes a popup, a dialog or the menu (背包 / 技能 / 法宝 / 设置). " +
  "In a stage without a menu use pause instead.", {},
  async () => {
    const r = await bridge.request("ui_back");
    return text({ ...r, ui: await bridge.request("ui_list") });
  });

// ---------------------------------------------------------------- direct control

async function act({ hold, press, seconds }) {
  runner.manualUntil = Date.now() + seconds * 1000 + 2000;
  const before = runner.events.length;
  await bridge.request("input", { hold, press });
  await sleep(seconds * 1000);
  await bridge.request("input", { hold: [], press: [] });
  runner.manualUntil = 0;
  const evs = runner.events.slice(before).filter((e) => e.ev !== "log").map(({ at, ...e }) => e);
  return { obs: await bridge.request("observe"), events: evs };
}

tool("act", "Hold some actions (and tap others once) for a short time, then let go. A running script pauses meanwhile. " +
  "Returns the state after it and the events during it. Times are real seconds (at speed 2 the game runs 2x as far).",
  { hold: actionList, press: actionList, seconds: z.number().min(0.05).max(3).default(0.3) },
  async (a) => text(await act(a)));

tool("sequence", "Run up to 64 steps in order: each {hold?, press?, seconds} (seconds 0..3; a step with no keys waits). " +
  "One call runs for 10 s at most; then it returns where it stopped (next) so you can send the rest.",
  { steps: z.array(z.object({ hold: actionList, press: actionList, seconds: z.number().min(0).max(3).default(0.2) })).max(64) },
  async ({ steps }) => {
    const end = Date.now() + 10000;
    const before = runner.events.length;
    let i = 0;
    for (; i < steps.length; i++) {
      const s = steps[i];
      if (Date.now() + s.seconds * 1000 > end) break;
      runner.manualUntil = Date.now() + s.seconds * 1000 + 2000;
      await bridge.request("input", { hold: s.hold, press: s.press });
      await sleep(s.seconds * 1000);
    }
    await bridge.request("input", { hold: [], press: [] });
    runner.manualUntil = 0;
    const evs = runner.events.slice(before).filter((e) => e.ev !== "log").map(({ at, ...e }) => e);
    return text({ done: i, of: steps.length, next: i < steps.length ? i : null, events: evs,
      obs: brief(await bridge.request("observe")) });
  });

// ---------------------------------------------------------------- scripts

const scriptFile = (name) => join(SCRIPTS, basename(name).replace(/[^\w\-\u4e00-\u9fff]/g, "_") + ".js");

function codeOf({ code, name }) {
  if (code) return code;
  if (name) {
    const f = scriptFile(name);
    if (existsSync(f)) return readFileSync(f, "utf8");
    const ex = join(ROOT, "examples", basename(name) + ".js");
    if (existsSync(ex)) return readFileSync(ex, "utf8");
    throw new Error("no saved script " + name);
  }
  throw new Error("give code or name");
}

tool("script_check", "Compile a script and try it once on the current state (or a sample state); reports errors and " +
  "what it would press. Nothing is sent to the game.",
  { code: z.string(), params: z.record(z.any()).default({}) },
  async ({ code, params }) => {
    let obs = runner.lastObs;
    try { obs = await bridge.request("observe"); } catch { /* not connected: the sample */ }
    if (!obs) obs = JSON.parse(readFileSync(join(ROOT, "docs", "sample-obs.json"), "utf8"));
    const box = await ScriptBox.create(code);
    try {
      let memo = {};
      const logs = [];
      for (const fn of ["onStart", "onTick"]) {
        const r = box.call(fn, obs, memo, params);
        if (r === null) return text({ ok: false, error: `${fn} took longer than 20 ms` });
        memo = r.memo;
        logs.push(...r.out.logs);
        if (fn === "onTick") return text({ ok: true, hz: box.hz, input: cleanInput(r.ret), memo, logs, wakes: r.out.wakes, done: r.out.done });
      }
    } finally { box.dispose(); }
  });

tool("script_run", "Run a script in the background (replaces the running one). It is called hz times a second with the " +
  "state and returns the keys to hold / tap. Use wait_events to follow it.",
  { code: z.string().optional(), name: z.string().optional().describe("a saved script or an example"),
    params: z.record(z.any()).default({}) },
  async (a) => text(await runner.startScript(codeOf(a), a.name, a.params)));

tool("script_update", "Replace the running script's code, keeping its memo unless keep_memo is false.",
  { code: z.string(), keep_memo: z.boolean().default(true) },
  async ({ code, keep_memo }) => text(await runner.updateScript(code, keep_memo)));

tool("script_stop", "Stop the running script and let go of every key.", {},
  async () => text({ stopped: runner.stopScript("stopped by agent") }));

tool("script_save", "Save a script under a name (with a one-line description) for later.",
  { name: z.string(), code: z.string(), description: z.string().default("") },
  async ({ name, code, description }) => {
    mkdirSync(SCRIPTS, { recursive: true });
    writeFileSync(scriptFile(name), `// ${description.replace(/\n/g, " ")}\n${code}`);
    return text({ saved: name });
  });

tool("script_list", "Saved scripts and the bundled examples, with their descriptions.", {}, async () => {
  const list = (dir, kind) => existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".js")).map((f) => ({
    name: f.slice(0, -3), kind, description: (readFileSync(join(dir, f), "utf8").split("\n")[0] || "").replace(/^\/\/\s?/, "") })) : [];
  return text([...list(SCRIPTS, "saved"), ...list(join(ROOT, "examples"), "example")]);
});

tool("script_load", "The code of a saved script or example.", { name: z.string() }, async ({ name }) => text(codeOf({ name })));

// ---------------------------------------------------------------- waiting and watching

tool("wait_events", "Wait until the watchdog wakes you (boss, low HP, stage end, stuck, a watched drop, script done / " +
  "error / ctx.wake) or `seconds` pass. Returns a one-line summary, the notable events and the state.",
  { seconds: z.number().min(0.5).max(60).optional() },
  async ({ seconds }) => text(await runner.waitEvents(seconds)));

tool("watch_config", "Read or change when the watchdog wakes you. Defaults: " + JSON.stringify(WATCH_DEFAULTS),
  { hp_below: z.number().min(0).max(1).optional(), stuck_sec: z.number().min(3).max(600).optional(),
    boss: z.boolean().optional(), stage_end: z.boolean().optional(), drops: z.array(z.string()).optional(),
    heartbeat_sec: z.number().min(1).max(60).optional(), max_wakes_per_min: z.number().min(1).max(60).optional() },
  async (patch) => {
    for (const [k, v] of Object.entries(patch)) if (v !== undefined) runner.watch[k] = v;
    return text(runner.watch);
  });

tool("set_speed", "Game speed 1..4 (physics runs proportionally faster, so the game plays the same, only sooner).",
  { speed: z.number().min(1).max(4) },
  async ({ speed }) => text(await bridge.request("speed", { value: speed })));

tool("pause", "on: open the in-stage menu (pauses). off: close any open menu (in a stage or on the map) and resume.", { on: z.boolean().default(true) },
  async ({ on }) => text(await bridge.request("pause", { value: on })));

// ---------------------------------------------------------------- goals

function loadGoals() {
  return existsSync(GOALS) ? JSON.parse(readFileSync(GOALS, "utf8")) : {};
}

tool("goal", "A long task's ledger, kept across sessions: set a goal with its steps, update steps, read it. " +
  "Steps are {name, done?, note?}.",
  { action: z.enum(["get", "set", "update", "clear"]).default("get"), name: z.string().optional(),
    text: z.string().optional(), steps: z.array(z.object({ name: z.string(), done: z.boolean().default(false),
      note: z.string().optional() })).optional() },
  async ({ action, name, text: t, steps }) => {
    const g = loadGoals();
    if (action === "get") return text(name ? g[name] ?? null : g);
    if (!name) throw new Error("name needed");
    if (action === "clear") delete g[name];
    else if (action === "set") g[name] = { text: t ?? "", steps: steps ?? [], updated: new Date().toISOString() };
    else {
      const cur = g[name] ?? { text: "", steps: [] };
      if (t !== undefined) cur.text = t;
      for (const s of steps ?? []) {
        const old = cur.steps.find((x) => x.name === s.name);
        if (old) Object.assign(old, s); else cur.steps.push(s);
      }
      cur.updated = new Date().toISOString();
      g[name] = cur;
    }
    mkdirSync(STATE, { recursive: true });
    writeFileSync(GOALS, JSON.stringify(g, null, 1));
    return text(g[name] ?? null);
  });

// ---------------------------------------------------------------- resources

const doc = (uri, file, description) => server.registerResource(file, uri, { description, mimeType: "text/markdown" },
  async () => ({ contents: [{ uri, text: readFileSync(join(ROOT, "docs", file), "utf8") }] }));
doc("zmxy2://docs/script-api", "script-api.md", "How to write a script: hooks, ctx, the state, the actions");
doc("zmxy2://docs/game", "game.md", "Controls, the three heroes' skills, the screens and the stages");

await server.connect(new StdioServerTransport());
log(`MCP ready; game connection string: ${bridge.url}`);
