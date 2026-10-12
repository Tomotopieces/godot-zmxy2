---
name: stage-rework
description: Rework a stage of the 造梦西游2 Godot remake - turn its baked art into an editor scene the user arranges by hand (parallax layers, tiled TextureRects, mechanisms as scenes with scripts) and give it a lighting/weather look (StageLighting). Use when asked to "转场景", rebuild a stage like 1-1/1-2/1-3, or design a stage's visual style.
---

# Stage rework (1-1 鬼城, 1-2 无常巷, 1-3 鬼门关 are the reference results)

Read `game/scenes/levels/README.md` first (structure, conventions). The user hand-edits the scenes afterwards: **never
regenerate over an existing scene** (`level_to_scene.gd` refuses without `--force`; `git status` shows their uncommitted edits - do not
commit or overwrite them unless you must touch the file, then edit it as text and say so).

## A. Level data -> scene

1. **Extract the original bitmaps as loose pieces** (every placement its own piece, never glued or rasterised into strips):
   `node tools/rig/extract_level.js <area> <stage> game/assets/levels/sl<area><stage>` (e.g. `1 3` -> sl13). Bg shapes are decomposed by
   `shape_tiles.js decomposeLoose`; the log lists skipped non-bitmap records.
2. **Find the junk bitmaps**: view textures (`node tools/_sheet3.js out.png <png...>` makes a contact sheet; `_crop.js`, `_view.js` too -
   scratch helpers in tools/, git-ignored, recreate if missing). The "4399" logo bitmap and the grey/blue gradient "fake fog" strips are
   dropped per level: add the keys to `DROP` in `tools/rig/drop_overlays.js` (symbol ids differ per level: 1-1 `1_v6:30,87`, 1-2 `30,60`, 1-3 `30,2`),
   run it, then `node tools/rig/dedupe.js` (stores identical PNGs once, names them `<lib>_<id>.png` via `organize_shared.js`, refreshes scene uids).
3. **Import + rebuild**: `godot --headless --path game --import`, then `bash tools/rig/rebuild_all.sh` if any rig texture moved (compressed
   `anims.res` embed texture paths - grep cannot see them; symptom: "Resource file not found: res://assets/shared/<md5>.png"). Delete
   `game/.godot/exported` (Recycle Bin; it is a directory: use `[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(path, 'OnlyErrorDialogs', 'SendToRecycleBin')`) if stale refs persist.
4. **Generate the scene**: `godot --headless --path game res://tools/level_to_scene.tscn -- sl13 --far=<keys> --fog=<keys> [--near=<keys>]`.
   - far = distant silhouettes (houses), fog = haze strips (the 360-wide repeating bitmap), near = pieces to force into the near layer;
     tall pieces by an exit door go near automatically. Pick the keys from the contact sheet / the texture keys with their counts in level.json.
   - Result: `Far` Parallax2D 0.8, fog TextureRects under `Art`, `Middle` 0.9, `Near` 1.0, `Ground`; x of a piece in a layer = s * original x.
   - Runs of 3+ identical pictures edge to edge (haze, floor) become ONE TextureRect: texture_repeat on, stretch Tile, **texture_filter Nearest**.
5. **Mechanisms** (doors, switches...) whose art lives inside a rig: put them in `scenes/objects/<name>.tscn` with a script on the root
   (`src/level/objects/<name>.gd`, `@export` parameters, a `Guides` node for editor-only boxes), instance it under `Scenery/Objects/<Name>` at its
   **real world position** (take it from `game/data/stages.json` / the old stage script - NOT from level.json `doors`, which can be wrong; 1-2's
   white-bone door is at (2270, 336)). Strip the decoration parts the rig drew itself from its `rig.json` (texture + track) and rebuild that rig
   (`build_rig.gd`), otherwise they reappear at run time. Rebuild the rig's animation **completely** (every track: texture, position, region, offset,
   visibility) - a texture-only copy leaves pieces stuck (the leaves on the white-bone door). Delete the old stage script / stages.json entries,
   point `tools/stage_test.gd` at the node. Mechanisms get no parallax.
6. Wire the lighting file (section B) and README notes; commit on the `visual` branch (art work lives there).

Some stages are not pieces at all: 5-1 白骨精 is ONE finished 940x590 painting (skeleton, moon, mist) plus a floor strip. Do not try to cut it up. Generate the scene with the painting forced into
`--near=` (a fixed-camera room: a Parallax2D below 1.0 would shift it by (1-s) x half a screen), tile the floor, and design the look for a painted backdrop: light dimming/tint,
no rim light and no feet fade on it (`rim:0, fade:0` for its layer), the glow and mist added around it.

## B. Look design (data/lighting/<stage>.json -> src/level/stage_lighting.gd)

Methodology - decide the **mood in one sentence** per stage first, then express it with a fixed set of knobs, always in this order:
1. **Value structure**: dim scenery/ground/far (`scene.art/ground/far` multipliers, far a little lighter = aerial perspective), dim actors less (`body.shade/lit`),
   never dim pickups/numbers/HUD. Night is cool blue; other moods change the hue, not the pipeline.
2. **One light logic**: a source (moon, upper left) drives everything consistently: rim light on the facing edges (`rim_*`, `art_look.gdshader`, keep thin: 2 px),
   body rim (`Rig.set_light`), shadow direction (`shadow.shear/squash/blur`: small shear, soft edge, alpha by mood). Light shafts / moon glow live in the sky layer
   **behind** scenery and actors (CanvasLayer -1). No light source (overcast) = drop `moon`, keep rim low.
3. **Depth**: fade decoration to dark at the feet (`fade_height/fade_dark`), per-layer tint/blur (`layers.Far.blur`, `tint`) - aerial perspective, slight DOF.
4. **Atmosphere**: mist (`fog.*`, shader-driven, never a baked strip), a patchy layer behind actors + a thin one in front; density scales the mood (1-1 heavy, 1-2 thin).
5. **Weather** (differentiate stages by it): `rain` (rain.gdshader: world-space x via `scroll`, one landing row `land_y`, streaks + splash ring/beads, `amount` x `density`,
   negative `slant` = leaning left, speed/length scale the intensity), `lightning` (screen flash with 3 pulses + a sky bolt, `interval/strength`), `grade.brightness` for storms.
   Escalate across stages: 1-1 moonlit mist -> 1-2 no moon, drizzle -> 1-3 darker, 2x rain, thunder.
6. **Grade**: `grade.saturation/vignette/brightness` last, a global pass over the world (under the HUD).

Rules learned the hard way: effects stay out of gameplay (nothing covers actors; nothing screen-fixed that should be world-fixed); weather has its own RNG (never the
gameplay `Rng`); the project is Forward+ with 2D MSAA (no Compatibility-only tricks); numbers live in the json, not the code; every effect is optional by key so a stage
without it is untouched. Check with `godot --path game --position 6000,6000 res://tools/light_shot.tscn -- <a,b> <out.png> <camera x> [monster ids] [wait s] [strike s]` and view the
png. Do not take screenshots to judge anti-aliasing - the user judges. Headless cameras do not follow a hero teleported far away: shoot the first screen or move the thing under test.

## C. Gotchas
- The user's mid-turn feedback usually corrects scope ("only far/near", "don't glue pieces", "interactive things get no parallax") - follow it literally.
- CRLF repo files: edit with the Edit tool or scripts that split on `\r\n`; shell heredocs eat backslashes (regexes!) - write JS/GDScript helpers with the Write tool.
- `class_name` scripts need `godot --headless --path game --import` before a headless run sees them; autoloads are missing under `-s` scripts, use a tiny scene runner instead.
- Texture uid mismatch after dedupe makes scenes "fail to load: missing dependency": `node tools/rig/fix_scene_uids.js --fix` (rebuild_all.sh does it).
- Delete = Recycle Bin (`bash tools/trash.sh <file>`), never rm. Answer the user in Simplified Chinese; report what was and was not verified.
- Tests: the user does not want the full suite run for art work; run targeted checks only (`stage_test`, `ai_trace -- --check` when shared code changed).
