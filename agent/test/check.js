// Offline checks: the sandbox, the examples, and the MCP server talking to a fake game over the WebSocket.
import { spawn } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import WebSocket from "ws";
import { ScriptBox, cleanInput } from "../src/sandbox.js";

let failed = 0;
const ok = (c, m) => { console.log((c ? "ok   " : "FAIL ") + m); if (!c) failed++; };
const obs = JSON.parse(readFileSync(new URL("../docs/sample-obs.json", import.meta.url)));

for (const f of readdirSync(new URL("../examples/", import.meta.url))) {
  const box = await ScriptBox.create(readFileSync(new URL("../examples/" + f, import.meta.url), "utf8"));
  const r = box.call("onTick", obs, {}, {});
  ok(r !== null, `example ${f} runs (${JSON.stringify(cleanInput(r?.ret))})`);
  box.dispose();
}
try { await ScriptBox.create("export default {}"); ok(false, "a script without onTick is refused"); }
catch { ok(true, "a script without onTick is refused"); }
const loop = await ScriptBox.create("export default { onTick(){ while(true){} } }");
let stopped = false;
for (let i = 0; i < 12; i++) { try { loop.call("onTick", obs, {}, {}); } catch { stopped = true; break; } }
ok(stopped, "a looping onTick is stopped after 10 overruns");
loop.dispose();
const mem = await ScriptBox.create("export default { onTick(o,c){ c.memo.n=(c.memo.n||0)+1; c.log('n='+c.memo.n); return {press:['attack','fly']} } }");
const r1 = mem.call("onTick", obs, {}, {}); const r2 = mem.call("onTick", obs, r1.memo, {});
ok(r2.memo.n === 2 && r2.out.logs[0] === "n=2", "memo is kept between calls");
ok(JSON.stringify(cleanInput(r2.ret)) === '{"hold":[],"press":["attack"]}', "unknown actions are dropped");
mem.dispose();

// the server with a fake game
const port = 47900 + Math.floor(Math.random() * 50);
const srv = spawn(process.execPath, [new URL("../src/index.js", import.meta.url).pathname.replace(/^\/([A-Z]:)/, "$1")],
  { env: { ...process.env, ZMXY2_PORT: String(port), ZMXY2_TOKEN: "testtoken", ZMXY2_STATE_DIR: process.env.TEMP + "/zmxy2-mcp-test" }, stdio: ["pipe", "pipe", "pipe"] });
let buf = "";
const replies = new Map();
srv.stdout.on("data", (d) => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); try { const m = JSON.parse(l); if (m.id) replies.set(m.id, m); } catch {} } });
let rid = 0;
const rpc = async (method, params) => { const id = ++rid; srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  for (let i = 0; i < 200 && !replies.has(id); i++) await new Promise((r) => setTimeout(r, 50)); return replies.get(id); };
const call = async (name, args = {}) => { const r = await rpc("tools/call", { name, arguments: args }); return r?.result; };
await new Promise((r) => setTimeout(r, 800));
await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "check", version: "1" } });
srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
const tools = (await rpc("tools/list", {}))?.result?.tools?.map((t) => t.name) || [];
ok(tools.length >= 20, `tools listed (${tools.length})`);
const bad = new WebSocket(`ws://127.0.0.1:${port}/?t=wrong`);
const badClosed = await new Promise((r) => { bad.on("close", (c) => r(c)); bad.on("error", () => r(-1)); });
ok(badClosed === 4001, "a wrong token is refused");
const inputs = [];
const game = new WebSocket(`ws://127.0.0.1:${port}/?t=testtoken`);
await new Promise((r) => game.on("open", r));
game.send(JSON.stringify({ ev: "hello", version: "test" }));
game.on("message", (d) => { const m = JSON.parse(d); let result = true;
  if (m.op === "observe") result = obs;
  if (m.op === "input") inputs.push(m);
  if (m.op === "ui_list") result = { screen: "map", items: [{ id: "Stage1Level1", text: "1-1", enabled: true }] };
  game.send(JSON.stringify({ id: m.id, ok: true, result })); });
const st = await call("get_state", { fields: ["hero"] });
ok(st && JSON.parse(st.content[0].text).hero.role === "bajie", "get_state goes through the game");
const run = await call("script_run", { name: "clear_room" });
ok(run && !run.isError, "script_run starts an example");
await new Promise((r) => setTimeout(r, 600));
ok(inputs.length > 0, `the script sends input (${inputs.length} messages)`);
game.send(JSON.stringify({ ev: "boss_appear", name: "转轮王" }));
const w = await call("wait_events", { seconds: 5 });
const wj = w && JSON.parse(w.content[0].text);
ok(wj?.woke && wj.reasons[0].includes("转轮王"), "a boss wakes wait_events early");
const bad2 = await call("script_update", { code: "export default { onTick(){ throw new Error('boom') } }" });
const w2 = JSON.parse((await call("wait_events", { seconds: 5 })).content[0].text);
ok(w2.reasons.some((x) => x.includes("boom")), "a script error stops it and wakes the agent");
const ck = await call("script_check", { code: "export default { onTick(o){ return {hold:['left']} } }" });
ok(JSON.parse(ck.content[0].text).input.hold[0] === "left", "script_check runs on the current state");
game.close(); srv.kill();
console.log(failed ? `${failed} FAILED` : "ALL OK");
process.exit(failed ? 1 : 0);
