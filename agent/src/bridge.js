// The game connection: a WebSocket server on 127.0.0.1 that the game (AgentBridge) connects to as a client.
// Requests are {id, op, ...} -> {id, ok, result, error}; the game also pushes events {ev, ...}.
import { WebSocketServer } from "ws";
import { randomBytes } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";

const REQUEST_TIMEOUT = 15000;

/** A token kept across restarts (agent/state/token), so a connection string saved in the game keeps working. */
function loadToken(stateDir) {
  if (process.env.ZMXY2_TOKEN) return process.env.ZMXY2_TOKEN;
  const f = join(stateDir, "token");
  if (existsSync(f)) return readFileSync(f, "utf8").trim();
  const t = randomBytes(12).toString("hex");
  mkdirSync(dirname(f), { recursive: true });
  writeFileSync(f, t);
  return t;
}

export class GameBridge {
  constructor({ port, stateDir, log }) {
    this.port = port;
    this.token = loadToken(stateDir);
    this.log = log;
    this.sock = null;
    this.hello = null;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Set();
  }

  get url() {
    return `ws://127.0.0.1:${this.port}/?t=${this.token}`;
  }

  get connected() {
    return this.sock !== null && this.sock.readyState === 1;
  }

  start() {
    this.wss = new WebSocketServer({ host: "127.0.0.1", port: this.port, maxPayload: 8 << 20 });
    this.wss.on("connection", (ws, req) => {
      const t = new URL(req.url, "http://x").searchParams.get("t");
      if (t !== this.token) {
        ws.close(4001, "bad token");
        return;
      }
      if (this.sock) this.sock.close(4002, "replaced");
      this.sock = ws;
      this.log("game connected");
      ws.on("message", (data) => this.#onMessage(String(data)));
      ws.on("close", () => {
        if (this.sock !== ws) return;
        this.sock = null;
        this.hello = null;
        for (const p of this.pending.values()) p.reject(new Error("game disconnected"));
        this.pending.clear();
        this.#emit({ ev: "disconnected" });
        this.log("game disconnected");
      });
    });
    this.wss.on("error", (e) => this.log("ws server error: " + e.message));
  }

  onEvent(fn) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  #emit(ev) {
    for (const fn of this.listeners) {
      try { fn(ev); } catch (e) { this.log("listener error: " + e.message); }
    }
  }

  #onMessage(text) {
    let m;
    try { m = JSON.parse(text); } catch { return; }
    if (m.ev) {
      if (m.ev === "hello") this.hello = m;
      this.#emit(m);
      return;
    }
    const p = this.pending.get(m.id);
    if (!p) return;
    this.pending.delete(m.id);
    clearTimeout(p.timer);
    if (m.ok) p.resolve(m.result);
    else p.reject(new Error(m.error || "game error"));
  }

  /** One request to the game. */
  request(op, args = {}) {
    if (!this.connected) return Promise.reject(new Error("game not connected - start it with the connection string (tool connect_info)"));
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`game did not answer ${op}`));
      }, REQUEST_TIMEOUT);
      this.pending.set(id, { resolve, reject, timer });
      this.sock.send(JSON.stringify({ id, op, ...args }));
    });
  }

  /** Wait until the game connects (or the timeout passes). */
  async waitConnected(ms) {
    const end = Date.now() + ms;
    while (!this.connected && Date.now() < end) await sleep(200);
    return this.connected;
  }
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
