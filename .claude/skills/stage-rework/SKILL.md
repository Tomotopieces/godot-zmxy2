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
2. **Overlays**: leave the 4399 logo that is *embedded* in a texture (floor tile, rock...) alone - never scrub it (`remove_watermark.js` looked bad; do not run it). Bitmaps that are *only* the logo
   (an 83x36 "4399 4399 ..." bitmap, drawn at alpha 0.17) and the grey / tinted "fake mist" gradient strips lying along the ground (wide, low, low-contrast, half transparent: e.g. 1_v6:60, 2:608) are
   dropped: find them with `node tools/_find_overlays.js sl23 ...` (scratch helper, recreate if missing: flags 83x36 bitmaps and wide low-variance strips), LOOK at them on a contact sheet
   (`tools/_sheet3.js out.png <png...>`; floors and haze bands that look similar are real art), add the keys of that stage to `DROP` in `tools/rig/drop_overlays.js` (symbol ids differ per level), run it, then
   `node tools/rig/dedupe.js` (stores identical PNGs once, names them `<lib>_<id>.png` via `organize_shared.js`, refreshes scene uids). Never put a dropped piece back on your own, and never
   decide anything else for the user: only these two kinds are removed.
3. **Import + rebuild**: `godot --headless --path game --import`, then `bash tools/rig/rebuild_all.sh` if any rig texture moved (compressed
   `anims.res` embed texture paths - grep cannot see them; symptom: "Resource file not found: res://assets/shared/<md5>.png"). Delete
   `game/.godot/exported` (Recycle Bin; it is a directory: use `[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(path, 'OnlyErrorDialogs', 'SendToRecycleBin')`) if stale refs persist.
4. **Generate the scene**: `godot --headless --path game res://tools/level_to_scene.tscn -- sl21` (no other arguments).
   - **The tool does not decide depth**: every decoration piece goes into `Art/Near` (Parallax2D 1.0) at its original x; `Art/Far` (0.8) and `Art/Middle` (0.9) are created EMPTY.
     The user does the layering himself (moving a piece to a layer = x * the layer's scale). Do not move pieces between layers on your own, do not guess "far" or "fog" bitmaps.
     Only when he asks you to move pieces: convert x (x_layer = s * x_orig, back: x_orig = x_layer / s), keep the painting order (far pieces first, then middle, then what was in front).
   - The stage's **sky picture** (`far` of level.json) is in the scene too: `Background` (CanvasLayer -2) / `Sky` (Sprite2D). Level scrolls it over the stage length from where the sprite stands (`_far_x0`).
   - Every stage gets a scene (sl01 is the debug arena). A stage whose background is one painting + a floor (boss rooms) simply has 2 nodes.
   - Runs of 3+ identical pictures edge to edge (haze, floor) become ONE TextureRect (2+ for the floor): texture_repeat on, stretch Tile, **texture_filter Nearest**. The floor must be ONE
     TextureRect (the original lays it in 2-3 strips, an original quirk). A haze strip that starts at an odd x (the original's bug) is moved to x 0.
5. **Mechanisms** (doors, switches...) whose art lives inside a rig: put them in `scenes/objects/<name>.tscn` with a script on the root
   (`src/level/objects/<name>.gd`, `@export` parameters, a `Guides` node for editor-only boxes), instance it under `Scenery/Objects/<Name>` at its
   **real world position** (take it from `game/data/stages.json` / the old stage script - NOT from level.json `doors`, which can be wrong; 1-2's
   white-bone door is at (2270, 336)). Strip the decoration parts the rig drew itself from its `rig.json` (texture + track) and rebuild that rig
   (`build_rig.gd`), otherwise they reappear at run time. Rebuild the rig's animation **completely** (every track: texture, position, region, offset,
   visibility) - a texture-only copy leaves pieces stuck (the leaves on the white-bone door). Delete the old stage script / stages.json entries,
   point `tools/stage_test.gd` at the node. Mechanisms get no parallax.
   **No rig inside a stage scene.** A rig (Rig node, rig.json/anims.res) is for characters and effects. A mechanism whose art is a few pictures (the white-bone door, the boat) is built from plain Sprite2D nodes
   (visible in the editor) with a normal AnimationPlayer for whatever really animates (door leaves, the water ripple); never instance a rig for it (its parts are hidden until it plays, and it drags the rig machinery in).
   Move the pictures next to the stage (`assets/levels/<stage>/tex`) and delete the now unused rig.
6. Wire the lighting file (section B) and README notes; commit on the `visual` branch (art work lives there).

Some stages are not pieces at all: 5-1 白骨精 is ONE finished 940x590 painting (skeleton, moon, mist) plus a floor strip. Do not try to cut it up. The generator puts it in Near like any piece (a fixed-camera
room: a Parallax2D below 1.0 would shift it by (1-s) x half a screen); design the look for a painted backdrop: light dimming/tint, no rim light or feet fade on it (`rim:0, fade:0` for its layer), mist/rain around it.

## B. Look design (data/lighting/<stage>.json -> src/level/stage_lighting.gd)

Methodology - decide the **mood in one sentence** per stage first, then express it with a fixed set of knobs, always in this order:
1. **Value structure**: dim scenery/ground/far (`scene.art/ground/far` multipliers, far a little lighter = aerial perspective), dim actors less (`body.shade/lit`),
   never dim pickups/numbers/HUD. Night is cool blue; other moods change the hue, not the pipeline.
2. **One light logic**: find the stage's own light source and make everything agree with it. The rim light (a thin 2 px highlight on the edges facing a light, `rim_*`, `art_look.gdshader`, body rim
   `Rig.set_light`) and the moon glow / shafts exist **because 1-1..1-3 have a moon** - they are not a general setting. A new style is designed from scratch: ask what lights this place (a pillar of light
   from above, lava glow from below, lanterns, nothing) and set rim (`rim_strength 0` to switch it off), shadows (`shadow.shear/squash/blur/alpha`: direction and softness follow the source), glow and shafts
   (`moon` key, any light in the sky: behind scenery and actors, CanvasLayer -1) accordingly. No source (overcast) = drop `moon`, no rim.
3. **Depth**: fade decoration to dark at the feet (`fade_height/fade_dark`), per-layer tint/blur (`layers.Far.blur`, `tint`) - aerial perspective, slight DOF.
4. **Atmosphere**: mist (`fog.*`, shader-driven, never a baked strip), a patchy layer behind actors + a thin one in front; density scales the mood (1-1 heavy, 1-2 thin).
5. **Weather** (differentiate stages by it): `rain` (rain.gdshader: world-space x via `scroll`, one landing row `land_y`, streaks + splash ring/beads, `amount` x `density`,
   negative `slant` = leaning left, speed/length scale the intensity), `lightning` (screen flash with 3 pulses + a sky bolt, `interval/strength`), `grade.brightness` for storms.
   Escalate across a set of related stages: 1-1 moonlit mist -> 1-2 no moon, drizzle -> 1-3 darker, 2x rain, thunder; a new area gets its own mood (2-1: violet underworld lit by a pillar of light from above, no rim).
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
