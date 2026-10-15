# 造梦西游2：十殿阎罗篇 — Godot 重制

Godot 4.7 (Forward+, 2D MSAA) remake of the Flash game 《造梦西游2》. The original's numbers and behaviour are kept; everything is rebuilt natively.
Playable: 孙悟空 / 唐僧 / 猪八戒 (八戒 unlocks with the first 红孩儿 kill). Stages are named `sl<area><level>`: `sl11` = 1-1 … `sl33`, `sl41`; hidden stages `sl51` (5-1 白骨精) … `sl111`; `sl01` = debug arena.
Answers to the user: Simplified Chinese. Deleting files: Recycle Bin (`bash tools/trash.sh <file>`), never `rm`.

## Layout
| Path | What |
|---|---|
| `game/` | the Godot project. `src/`: `actors` (hero, monster, `brains/` = per-monster AI, `heroes/`, `treasures/`), `combat` (hit, projectile, fx), `core` (game_state, layers, rng, save, forge, controls), `data` (resources), `items`, `level` (level, stage_lighting, shaders, `stages/` stage scripts, `objects/` mechanism scripts), `rig` (animated sprite rigs), `screens`, `ui` |
| `game/src/core/layers.gd` | screen size (940x590) and z-order constants (`Layers.Z_*`): never use a raw `z_index` number |
| `game/scenes/levels/<stage>.tscn` | the scenery of every stage (editor scenes, see "Stage scenes") |
| `game/scenes/objects/*.tscn` | stage mechanisms as scenes with a script on the root (`baigu_door`, `boat`) |
| `game/scenes/ui/<name>.tscn` | UI layouts as editor scenes (one per `assets/ui/<name>/ui.json`, see "UI scenes") |
| `game/assets/` | `rigs/<name>/` (rig.json + generated .tscn/anims.res), `levels/<stage>/` (level.json + `tex/`), `ui/`, `items/`, `sounds/`, `shared/<rigs\|ui\|levels\|mixed>/` (textures several things use) |
| `game/data/` | baked gameplay data (`.tres`, `stages.json`) and `lighting/<stage>.json` (per-stage look). Do not hand-edit baked files |
| `tools/data/*.json` | source of the gameplay numbers → `game/tools/bake_data.gd` → `game/data/` |
| `tools/rig/*.js` | extractors: decompiled SWF (`decomp/`, `swf/`, not in git; made by `tools/scripts/*.sh` + `tools/ffdec`) → `game/assets/**`. Texture names are `<flash library>_<symbol id>.png` |
| `.claude/skills/stage-rework/` | the procedure for turning a stage into an editor scene + designing its look |

## Run / test / export
- Run: open `game/` in Godot 4.7 (F5). Debug builds: `~` console (items, teleport, boss fight), keys 1 refill / 2 hit boxes / 3 test gear / 4 kill all / 5 restart / 6 invincible. F11 fullscreen.
- Checks (headless, exit code = result): `bash tools/run_checks.sh [filter]` — camera/walk/pad/role/bag/forge/treasure/smoke tests, `stage_test` (door12, hub), frame-exact AI traces of every monster (`ai_trace`, baselines `game/tools/ai_traces/`; regenerate with `-- --ids=…` after an intended AI change) and `loot_check`. Art work needs only targeted checks.
- Screenshots: `godot --path game --position 6000,6000 res://tools/light_shot.tscn -- <area,level> <out.png> <camera x> [monster ids] [wait s] [strike s]` (stage with its lighting); also `game/tools/{ui_shot,stage_shot,rig_shot,rig_strip,seam_check,skill_shot,fx_gallery}`.
- Export: `bash tools/build.sh` → `build/zmxy2_<branch>_v<version>.exe` (4.7.2 export templates).
- Saves: `user://slot_N.json` (`core/save_game.gd`). Items are `Item` objects. Gameplay randomness only through `Rng` (weather uses its own generator).
- Godot headless: `class_name` scripts need `godot --headless --path game --import` first; autoloads do not exist under `-s` scripts (use a tiny scene runner); Windows shell heredocs eat backslashes and many files are CRLF — edit with the Edit tool or scripts that split on `\r\n`.

## Pipeline (original → game)
1. `tools/rig/batch.sh specs_*.txt` extracts rigs (bodies, effects, bullets, monsters) and builds their scenes, then `dedupe.js` (identical PNGs stored once, `organize_shared.js` names/places them) and `rebuild_all.sh` (rebuilds every rig; **needed whenever a texture moved: `anims.res` embeds texture paths**; also runs `fix_scene_uids.js`).
2. Levels: `node tools/rig/extract_level.js <area> <level> game/assets/levels/sl<area><level>` → `level.json` (walls, stops, spawners, doors, art leaves, sky) + `tex/`; `drop_overlays.js` removes, per stage, the bitmaps that are only the "4399" logo or a grey "fake mist" strip; then `dedupe.js`.
3. Gameplay data: edit `tools/data/*.json`, run `game/tools/bake_data.gd`.
4. Never scrub the 4399 logo embedded inside a texture (`remove_watermark.js` looked bad, do not run it).

## Stage scenes
Every stage's scenery is an editor scene `scenes/levels/<stage>.tscn`; `Level` uses it instead of the `art` list of `level.json`. Walls, camera stops, spawners and exits still come from `level.json`; the look from `data/lighting/<stage>.json`. The user arranges these scenes by hand: **never regenerate an existing one** (`level_to_scene.gd` refuses without `--force`; `git status` shows his uncommitted edits — do not overwrite them).
Generate once: `godot --headless --path game res://tools/level_to_scene.tscn -- sl21`.
- A mechanism built from rigs: `godot --headless --path game res://tools/rig_to_object.tscn -- <out res> <RootName> <script res> <Child>=<rig>:<anim> [...]` merges those rigs into one scene with plain parts (renamed `<Child>Part<n>`) and keeps each rig's hit / hurt box as the root's `hit_rect_<child>` meta.
- `Scenery/Guides` editor-only reference lines (dropped at run time); `Background/Sky` (CanvasLayer -2) the sky picture, scrolled by `Level` over the stage length; `Art/{Far 0.8, Middle 0.9, Near 1.0}` `Parallax2D` layers; `Ground` the floor; `Objects` mechanisms.
- The tool puts **every** decoration piece in `Near` at its original x and leaves `Far`/`Middle` empty: the layering is the user's job. A piece moved to a layer has x = scroll_scale × original x. Never decide depth for him.
- Every bitmap placement of the original is its own `Sprite2D` (named `<bitmap>_<n>`, painting order); nothing is merged. A row of one picture laid edge to edge (floor, haze) is ONE `TextureRect`: repeat on, stretch Tile, texture filter Nearest. The floor is one TextureRect.
- Mechanisms (white-bone door of 1-2, 刑天门 of 2-2 / 2-3 / 11-1, boat of 3-1) are scenes of their own with a script on the root and `@export` parameters, instanced under `Objects` at their real world position (no parallax), built from plain Sprite2D + AnimationPlayer — **never a Rig** (parts are hidden in the editor). `Level` moves `Objects` into the world; the stage script (`stages/<stage>.gd`) finds them there. `level_to_scene.gd` does not make `Objects`.
- 5-1 (and boss rooms) have one painting + a floor: 2 nodes. 2-2 (`sl22`) was ONE baked 4700x522 JPEG in the original; it was rebuilt from the loose bitmaps of 2-3 by template matching (positions inferred); only the boss end (x ≥ 3745) stays a crop of the baked bitmap.
- Textures: `assets/levels/<stage>/tex/<lib>_<id>.png`; shared ones in `assets/shared/levels/`. After merging identical textures a scene's texture uids can go stale ("missing dependency"): `node tools/rig/fix_scene_uids.js --fix`.

## UI scenes
Every UI layout is an editor scene `scenes/ui/<name>.tscn`; `UiLayout.create()` instantiates it, and builds the layout from `assets/ui/<name>/ui.json` only when the scene does not exist (the json stays the generator and the fallback). The user arranges these scenes by hand: **never regenerate an existing one** (`ui_to_scene.gd` refuses without `--force`).
Generate once: `godot --headless --path game res://tools/ui_to_scene.tscn -- <name|all>` (`all` = every `assets/ui/*/ui.json`); `--force` overwrites.
The json build stays the only place that knows the data, so the tool writes what the game would have built: every node keeps the metas the run-time wiring reads — `ui_piece` (the names the code reaches it by, e.g. `backbtn` or `introducemc/skill1`), `ui_button` (a button's name) and `ui_bar` (a gauge holder's full / empty travel) — plus `labels`, `rec`, `tex_key`, `rest`. `UiLayout._wire_from_scene()` rebuilds `_named` / the buttons / the bars from them. A node may therefore be moved anywhere by hand, but **the code keeps reaching it only if its name and its metas survive**; a button keeps its `Up` / `Over` / `Down` children and a bar its `Clip` / `Content` (found by name).
The 背包 and 法宝 panels' attribute rows are such nodes: a `StatRow` (`src/ui/stat_rows.gd`, `@tool`) with a right-aligned `Caption` label and a `Box` (a `Panel` whose frame is a `StyleBoxFlat` saved in the scene) holding that row's value label — move or resize a whole row, its box or its caption by hand, and add rows by copying one; **keep every value label's name** (e.g. `txt_hp`), since it is also its `ui_piece` and `UiLayout._wire_from_scene()` keeps reaching it through the box (`set_text()` keeps working). The panels no longer build the rows at run time; `tools/ui_stat_rows_to_scene.gd` was the one-off migration of the two scenes (it refuses to run twice).

## Stage look (`StageLighting`)
`game/src/level/stage_lighting.gd` reads `data/lighting/<stage>.json`; a stage without a file is drawn as the original. Every key is optional: `scene` (tints of art/ground/far, rim light, feet fade), `layers` (per-layer blur/tint/rim/fade by node name), `body`/`shadow` (actor light, soft shadow), `fog`, `moon` (glow + light shafts, sky layer behind everything), `rain` (`rain.gdshader`: world-space drops, one landing row, splashes), `lightning`, `grade` (saturation, vignette, brightness).
Done: 1-1 moonlit mist, 1-2 drizzle without moon, 1-3 thunderstorm, 5-1 same as 1-2. Rim light / moon exist because 1-1…1-3 have a moon — they are not a general setting; a new stage's style is designed from scratch (what lights this place?). 2-1's look was removed ("later"). Draw order: far/sky −2, moon −1, world 0, mist 1, grade 2, HUD 3.
The camera eases to its target (`Camera2D` position smoothing, `Level.CAMERA_SMOOTHING`).

## Game-systems notes
- Monster AI: one `MonsterBrain` per monster (`actors/brains/brain_<id>.gd`, templates `boss_b.gd` / `boss_d.gd`), parameters in `MonsterData.brain`. Hits: Hitbox/Hurtbox Area2D pairs keyed by the animation, de-duplicated per swing by serial (`combat/hit_dealer.gd`).
- Rigs (`rig/rig.gd`): characters and effects only; animation events (`finished`, `new_hit`, `call …`) come from `tools/rig/events.js` and are emitted by a method track.
- Activities (中秋 / 七夕 / 国庆) have a panel with on/off switches; 贪/嗔/痴 stacking, forge (`core/forge.gd`), treasures (`actors/treasures/`), skill/shop screens are in `screens/`.
- Docs of the original's analysis were removed from the tree; they live in git history (`git log --diff-filter=D --name-only -- docs`).

## Branches
`main` — released remake (v1.3.1). `visual` — art/look work (stage scenes, lighting, UI ink experiments `tools/ui_ink/`, `game/tools/look_lab*`/`ui_proto*` are prototypes); nothing here is merged into `main` yet.
