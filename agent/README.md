# zmxy2-remake-mcp

An MCP server that lets any MCP-capable agent (Claude Code, pi, Cursor, …) play 造梦西游2 重制版. The agent sees what a
player sees and presses what a player presses; for fights it writes small JavaScript scripts that run in a sandbox and
press keys many times a second, while it follows them through a watchdog and log summaries.

```
agent ──MCP (stdio)──> zmxy2-remake-mcp ──WebSocket 127.0.0.1──> the game (exe or web build)
```

## Install

```bash
cd agent && npm install
```

Add it to your harness as a stdio server, e.g.

```json
{ "mcpServers": { "zmxy2": { "command": "node", "args": ["<repo>/agent/src/index.js"] } } }
```

(Claude Code: `claude mcp add zmxy2 -- node <repo>/agent/src/index.js`.)

## Connect the game

The server listens on `127.0.0.1:47823` (env `ZMXY2_PORT`) and only accepts the game with its token. The tool
`connect_info` gives the connection string `ws://127.0.0.1:47823/?t=<token>`; the token is kept in `agent/state/token`,
so a string saved in the game keeps working. Then either

- exe: `launch_game` with the exe's path, or start it yourself with `--agent=<connection string>`;
- web build: add `?agent=<connection string, URL-encoded>` to the game's address;
- any build: 设置 → AI 接入, paste the string, 保存.

The game shows "AI 已接入" in its top right corner while connected. Clearing the string in 设置 turns it off.

## Tools

| | |
|---|---|
| `connect_info`, `launch_game` | the connection |
| `get_state`, `get_screenshot` | what is on the screen (JSON; a picture for models that read images) |
| `list_ui`, `press_ui` | menus, map, bag, dialogs: the pressable controls and pressing one (the gamepad's way) |
| `act`, `sequence` | direct key presses for short precise moves |
| `script_check`, `script_run`, `script_update`, `script_stop` | background scripts (resource `zmxy2://docs/script-api`) |
| `script_save`, `script_list`, `script_load` | a script library (`agent/state/scripts/`) and the examples (`agent/examples/`) |
| `wait_events`, `watch_config` | wait for the watchdog (boss, low HP, stage end, stuck, watched drops, the script's own wake / done / error) with a summary of what happened |
| `set_speed`, `pause` | game speed 1..4, pause |
| `goal` | a long task's ledger (`agent/state/goals.json`) |

Resources: `zmxy2://docs/script-api` (how to write scripts) and `zmxy2://docs/game` (controls, heroes, screens, stages).

## What the agent cannot do

It gets no hidden numbers (drop rates, AI states) and has no way to set stats, teleport or run code in the game: scripts
run on the server and can only return keys; the UI is pressed like a gamepad does. The server only listens on
127.0.0.1 and refuses connections without the token.

## Checks

```bash
npm run check          # sandbox, examples, the server against a fake game
node test/live.js      # the real game (Godot 4.7 at its default path, or env GODOT): a new 八戒 game through 1-1
```
