# zmxy2-remake — 造梦西游2：十殿阎罗篇 Godot 重制版

Godot 4.7 (Forward+, 2D MSAA) remake of the Flash game 《造梦西游2》. The original's numbers and behaviour are kept; everything is rebuilt natively.
Playable: 孙悟空 / 唐僧 / 猪八戒 (八戒 unlocks with the first 红孩儿 kill). Stages are named `sl<area><level>`: `sl11` = 1-1 … `sl33`, `sl41`; hidden stages `sl51` (5-1 白骨精) … `sl111`; `sl01` = debug arena.
Answers to the user: Simplified Chinese. Deleting files: Recycle Bin (`bash tools/trash.sh <path>`), never `rm`.

## Layout
| Path | What |
|---|---|
| `game/` | the Godot project. `src/`: `actors` (hero, monster, `brains/` = per-monster AI, `heroes/`, `treasures/`), `combat` (hit, projectile, fx), `core` (game_state, layers, rng, save, forge, controls), `data` (resources), `items`, `level` (level, stage_lighting, shaders, `stages/` stage scripts, `objects/` mechanism scripts), `rig` (`Rig`: the script of every actor scene), `screens`, `ui` |
| `game/src/core/layers.gd` | screen size (940x590) and z-order constants (`Layers.Z_*`): never use a raw `z_index` number |
| `game/scenes/levels/<stage>.tscn` | the scenery of every stage (see "Stage scenes") |
| `game/scenes/actors/<name>/<name>.tscn` | every animated body: heroes, monsters, effects, bullets, items (see "Actor scenes") |
| `game/scenes/objects/*.tscn` | stage mechanisms as scenes with a script on the root (`baigu_door`, `boat`, `aurora_gate`, `river_water`, `xingtian_door`, `hub_door`, `hub_statue`) |
| `game/scenes/ui/<name>.tscn` | UI layouts (see "UI scenes"); `scenes/main.tscn` is the title screen |
| `game/assets/` | textures and sounds: `rigs/<name>/` (`tex/`, `slots/` = equipment variants of the actor scenes), `levels/<stage>/` (level.json + `tex/`), `ui/`, `items/`, `sounds/`, `shared/` (textures several things use) |
| `game/data/` | gameplay numbers (`.tres` resources, `stages.json`; px and seconds) and `lighting/<stage>.json` (per-stage look) — edit them directly |
| `tools/rig/*.js` | level extraction from the decompiled SWF (`decomp/`, not in git) → `game/assets/levels/**`. Texture names are `<flash library>_<symbol id>.png` |
| `.claude/skills/stage-rework/` | how to rework a stage's scene and design its look |

## Run / test / export
- Run: open `game/` in Godot 4.7 (F5). Debug builds: `~` console (items, teleport, boss fight), keys 1 refill / 2 hit boxes / 3 test gear / 4 kill all / 5 restart / 6 invincible / 7 invulnerable monsters glow yellow (temporary). F11 fullscreen. In a stage: C bag, V skills, B treasure.
- Web build: `bash tools/export_web.sh` (preset "Web", single-threaded, saves in the browser's IndexedDB). It uses the loading shell `game/web_shell/shell.html` (the original loading picture and bar) and splits the pack into content-defined chunks (`tools/web_chunks.js` → `web/chunks/*.bin` + `web/pck.json`) and writes `web/sw.js`, a service worker that rebuilds `index.pck` from the chunks in the browser cache: an update downloads only the chunks that changed (a script edit is ~1 MB); test with `node tools/serve_web.js` → http://localhost:8060/. `web/` is committed (pck / wasm via LFS) and is published to GitHub Pages by `.github/workflows/pages.yml` on every push that changes it. The web export templates are in the 4.7.2 template bundle.
- Panels fade in/out with `UiFade` (`src/ui/ui_fade.gd`); screen changes (title → role select → map → stage) go through `ScreenFade` in `main.gd`.
- Checks (headless, exit code = result): `bash tools/run_checks.sh [filter]` — camera/walk/pad/role/bag/forge/treasure/smoke tests, `stage_test` (door12, hub), frame-exact AI traces of every monster (`ai_trace`, baselines `game/tools/ai_traces/`; regenerate with `-- --ids=…` after an intended AI change) and `loot_check`. Art work needs only targeted checks.
- Screenshots: `godot --path game --position 6000,6000 res://tools/light_shot.tscn -- <area,level> <out.png> <camera x> [monster ids] [wait s] [strike s]` (stage with its lighting); also `game/tools/{ui_shot,panel_shot,stage_shot,rig_shot,rig_strip,seam_check,skill_shot,fx_gallery}`.
- Export: `bash tools/build.sh` → `build/zmxy2_<branch>_v<version>.exe` (4.7.2 export templates).
- Saves: `user://saves/slot_N.json` (`core/save_game.gd`). Items are `Item` objects. Gameplay randomness only through `Rng` (weather uses its own generator).
- Godot headless: `class_name` scripts need `godot --headless --path game --import` first; autoloads do not exist under `-s` scripts (use a tiny scene runner); Windows shell heredocs eat backslashes and many files are CRLF — edit with the Edit tool or scripts that split on `\r\n`.
- Throw-away runner scenes must quit even when they fail: first line of `_ready()` = `get_tree().create_timer(<budget s>, true, false, true).timeout.connect(get_tree().quit.bind(2))`, then the work, then `get_tree().quit()`. Always run them under `timeout`.
- Live debugging (godot-ai MCP plugin, editor open): `project_run` the game, then `game_manage` ops `suspend` / `next_frame` / `resume` (pause and step frames), `get_scene_tree` / `get_node_info` (runtime state), `input_action` / `input_sequence` (frame-timed input), `editor_manage` op `game_eval` (run GDScript in the running game), `editor_screenshot` source `game`, `logs_read` source `game`.

## Data
- The scenes (stages, actors, UI, objects) and `game/data/` are hand-edited and are the source of truth: there are no generators for them any more.
- New original art for a stage: `node tools/rig/extract_level.js <area> <level> game/assets/levels/sl<area><level>` → `level.json` (walls, stops, spawners, doors, sky) + `tex/`; `drop_overlays.js` removes the bitmaps that are only the "4399" logo or a grey "fake mist" strip; `dedupe.js` stores identical PNGs once (`organize_shared.js` names/places them); `fix_scene_uids.js --fix` refreshes stale texture uids ("missing dependency"). Never scrub the 4399 logo embedded inside a texture.

## Stage scenes
Every stage's scenery is an editor scene `scenes/levels/<stage>.tscn` that the user arranges by hand (`git status` shows his uncommitted edits — never overwrite them). Walls, camera stops, spawners and exits come from `level.json`; the look from `data/lighting/<stage>.json`.
- `Scenery/Guides` editor-only reference lines (dropped at run time); `Background/Sky` (CanvasLayer -2) the sky picture, scrolled by `Level` over the stage length; `Art/{Far 0.8, Middle 0.9, Near 1.0}` `Parallax2D` layers; `Ground` the floor; `Objects` mechanisms.
- The layering is the user's job: never decide depth for him. A piece moved to a layer has x = scroll_scale × original x.
- Every bitmap placement of the original is its own `Sprite2D` (named `<bitmap>_<n>`, painting order); nothing is merged. A row of one picture laid edge to edge (floor, haze) is ONE `TextureRect`: repeat on, stretch Tile, texture filter Nearest.
- Mechanisms are scenes of their own with a script on the root and `@export` parameters, instanced under `Objects` at their real world position (no parallax), built from plain Sprite2D + AnimationPlayer — **never a Rig** (parts are hidden in the editor). `Level` moves `Objects` into the world; the stage script (`stages/<stage>.gd`) finds them there.
- 5-1 (and boss rooms) have one painting + a floor: 2 nodes. 2-2 (`sl22`) was ONE baked 4700x522 JPEG in the original; it was rebuilt from the loose bitmaps of 2-3; only the boss end (x ≥ 3745) stays a crop of the baked bitmap.
- Textures: `assets/levels/<stage>/tex/<lib>_<id>.png`; shared ones in `assets/shared/levels/`.

## Actor scenes
Every animated body is a **hand-edited** scene `scenes/actors/<name>/<name>.tscn` whose root script is `Rig` (`src/rig/rig.gd`); `Rig.create(name)` instantiates it.
- `Poses/<Action>` = the parts of one action (only the playing one is visible); `EquipSlot` parts change with the equipment (variants in `assets/rigs/<name>/slots/`).
- `Hitbox` / `Hurtbox` `Shape` tracks = attack and hurt boxes (position, size, disabled per key; any shape).
- Method tracks `ev_*` = gameplay events: `ev_new_hit` (a new hit may land), `ev_finished` (action over), `ev_set_vx` / `ev_set_vy` / `ev_set_vx_forward` (px/s) and `ev_scale_vx` (factor) = movement, `ev_stop_move`, `ev_call(name)` = skill hook, `ev_grounded_call(name)` = only when on the floor, `ev_boss_dead_fx`, `ev_shake`.
- An action lasts its animation length; tweak by moving keys / changing the length in the Animation panel. The animations are the text file `<name>_actions.tres`.

## UI scenes
Every UI layout is a **hand-edited** scene `scenes/ui/<name>.tscn`; `UiLayout.create(name)` instantiates it. The nodes the code reaches carry the metas the run-time wiring reads — `ui_piece` (the names the code reaches it by, e.g. `backbtn` or `introducemc/skill1`), `ui_button` (a button's name) and `ui_bar` (a gauge holder's full / empty travel), plus `labels`, `rest`. A node may be moved anywhere, but **the code keeps reaching it only if its name and its metas survive**; a button keeps its `Up` / `Over` / `Down` children and a bar its `Clip` / `Content` (found by name).
The 背包 / 法宝 attribute rows are instances of `scenes/ui/backpack/stat.tscn` (`caption`, `width`, `piece` = the value label's `ui_piece`); equipment sockets are `equipment_slot.tscn`, bag cells `slot.tscn`.

## Stage look (`StageLighting`)
`game/src/level/stage_lighting.gd` reads `data/lighting/<stage>.json`; a stage without a file is drawn as the original. Every key is optional: `use` (another stage's file as the base), `scene` (tints of art/ground/far, rim light, feet fade), `layers` (per-layer blur/tint/rim/fade by node name), `body`/`shadow` (actor light, soft shadow), `fog`, `moon`, `rain`, `lightning`, `lamps`, `glows`, `sway`, `ash` (floating particles), `stars`, `grade` (saturation, vignette, brightness).
Rim light / moon exist because 1-1…1-3 have a moon — they are not a general setting; a new stage's style is designed from scratch (what lights this place?). Draw order: far/sky −2, moon −1, world 0, mist 1, grade 2, HUD 3.

## Game-systems notes
- Monster AI: one `MonsterBrain` per monster (`actors/brains/brain_<id>.gd`, templates `boss_b.gd` / `boss_d.gd`), parameters in `MonsterData.brain`. Hits: Hitbox/Hurtbox Area2D pairs keyed by the animation, de-duplicated per swing by serial (`combat/hit_dealer.gd`).
- Activities (中秋 / 七夕 / 国庆) have a panel with on/off switches; 贪/嗔/痴 stacking, forge (`core/forge.gd`), treasures (`actors/treasures/`), skill/shop screens are in `screens/`.
- Docs of the original's analysis were removed from the tree; they live in git history (`git log --diff-filter=D --name-only -- docs`).

## Branches
`main` — released remake (remake 0.1: the scene-based remake with the new stage looks; earlier releases were v1.0…v1.3.1).
