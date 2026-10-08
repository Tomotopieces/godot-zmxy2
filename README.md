# 造梦西游2：十殿阎罗篇 — Godot 重制

Godot 4.7 remake of the Flash game (single hero: 孙悟空). The original's numbers are kept; everything is rebuilt natively.

## Layout
| Path | What |
|---|---|
| `game/` | the Godot project (`src/` code by area: `actors`, `combat`, `core`, `data`, `items`, `level`, `rig`, `screens`, `ui`) |
| `game/src/core/layers.gd` | screen size and the z-order constants (`Layers.Z_*`) — never use a raw `z_index` number |
| `tools/rig/*.js` | extractors: decompiled SWF (`decomp/`, not in git) → `game/assets/**` |
| `tools/data/*.json` → `game/tools/bake_data.gd` → `game/data/*.tres` | gameplay numbers; edit the JSON, re-bake, never the `.tres` |
| `tools/rig/batch.sh specs_*.txt` | extract + build rigs |
| `docs/analysis/`, `docs/items.md` | analysis of the original, item/drop table (`node tools/rig/item_report.js`) |

## Run / test / export
- Run: open `game/` in Godot 4.7 (`F5`). Debug builds only: `~` item console, F1 refill, F2 hit boxes, F3 test gear, F4 kill all, F5 restart.
- Checks (headless, exit code = result): `bash tools/run_checks.sh [filter]`. Visual tools: `game/tools/{ui_shot,rig_shot,seam_check,skill_shot}`.
- Export: `godot --headless --path game --export-release Windows ../build/zmxy2.exe` (needs the 4.7.2 export templates).
- Saves: `user://slot_N.json` (`core/save_game.gd`: versioned, atomic write, `.bak`, validated load). Items are `Item` objects (`items/item.gd`). Gameplay randomness goes through `Rng`. F11 toggles fullscreen; gamepad defaults in `core/controls.gd`.

## Branches
`main` — original-faithful remake (LXGW font). `remake` — original font substitutes (源柔黑体 / 思源黑体 / 思源宋体), icon, release export (tags `remake-v1.0`, `remake-v1.0.1`).
