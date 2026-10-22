// Live check against the real game: starts the MCP server, the game (non-headless, its own window) with the
// connection string, then drives a new 八戒 game through the title, the hero choice, the comic, the map and 1-1.
import { spawn } from "node:child_process";
const GD = process.env.GODOT || "C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe";
const port = 47950, token = "livetoken";
const srv = spawn(process.execPath, ["src/index.js"], { env: { ...process.env, ZMXY2_PORT: String(port), ZMXY2_TOKEN: token,
  ZMXY2_STATE_DIR: process.env.TEMP + "/zmxy2-mcp-live" }, stdio: ["pipe", "pipe", "inherit"] });
let buf = ""; const replies = new Map();
srv.stdout.on("data", (d) => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); try { const m = JSON.parse(l); if (m.id) replies.set(m.id, m); } catch {} } });
let rid = 0;
const rpc = async (method, params) => { const id = ++rid; srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  for (let i = 0; i < 1400 && !replies.has(id); i++) await new Promise((r) => setTimeout(r, 50)); return replies.get(id); };
const call = async (name, args = {}) => { const r = (await rpc("tools/call", { name, arguments: args }))?.result;
  const t = r?.content?.[0]?.text; if (r?.isError) console.log("  ! " + name + ": " + t); try { return JSON.parse(t); } catch { return t; } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
await sleep(700);
await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "live", version: "1" } });
srv.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
const game = spawn(GD, ["--path", "../game", "--position", "6000,6000", "--", `--agent=ws://127.0.0.1:${port}/?t=${token}`], { stdio: "ignore" });
const stop = () => { try { game.kill(); } catch {} srv.kill(); };
setTimeout(() => { console.log("TIMEOUT"); stop(); process.exit(3); }, 240000);
for (let i = 0; i < 60; i++) { if ((await call("connect_info")).connected) break; await sleep(500); }
console.log("connected", (await call("connect_info")).connected);
const press = async (id) => { const r = await call("press_ui", { id }); console.log("press", id, "->", r?.screen, r?.error || ""); await sleep(600); return r; };
let ui = await call("list_ui"); console.log("title ui:", ui.items.map((x) => x.id).join(" "));
await press("NewGame");
ui = await call("list_ui"); console.log("select ui:", ui.screen, ui.items.map((x) => x.id + (x.enabled ? "" : "(off)")).join(" "));
await press("BtnBajie");
for (let i = 0; i < 6; i++) { const s = await call("get_state"); if (s.screen !== "cartoon") break; await press("next"); }
ui = await call("list_ui"); console.log("map ui:", ui.screen, ui.items.filter((x) => x.enabled).map((x) => x.id).join(" "));
await call("set_speed", { speed: 2 });
await press("Stage1Level1");
await sleep(2500);
let s = await call("get_state");
console.log("stage:", s.screen, s.stage?.id, "hero", s.hero?.x, s.hero?.hp, "enemies", s.enemies?.length, "floors", s.stage?.floors?.length);
console.log("act:", JSON.stringify((await call("act", { hold: ["right"], seconds: 1 })).obs.hero.x));
await call("script_run", { name: "clear_room" });
for (let i = 0; i < 8; i++) {
  const w = await call("wait_events", { seconds: 20 });
  console.log("wait:", w.woke ? "WOKE " + w.reasons.join("; ") : "", "|", w.summary);
  if (w.reasons?.some((r) => /done|cleared|died|error/.test(r))) break;
}
s = await call("get_state", { fields: ["hero", "stage"] });
console.log("end:", s.hero?.level, s.hero?.hp, s.stage?.room + "/" + s.stage?.rooms, "door", s.stage?.door_open);
await sleep(4000);
ui = await call("list_ui"); console.log("after:", ui.screen, ui.items.map((x) => x.id + ":" + x.text).join(" "));
const back = ui.items.find((x) => /BackToMap|Replay/.test(x.id)); if (back) await press(back.id);
console.log("then:", (await call("get_state")).screen);
console.log("shot:", (await rpc("tools/call", { name: "get_screenshot", arguments: { scale: 0.3 } }))?.result?.content?.[0]?.type);
stop(); process.exit(0);
