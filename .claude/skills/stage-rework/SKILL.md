---
name: stage-rework
description: Rework a stage of the 造梦西游2 Godot remake - its hand-edited editor scene (parallax layers, tiled TextureRects, mechanisms as scenes with scripts) and its lighting/weather look (StageLighting). Use when asked to change a stage's scene, add a mechanism to it, or design a stage's visual style.
---

# Stage rework (1-1 鬼城, 1-2 无常巷, 1-3 鬼门关 are the reference results)

Read the "Stage scenes" section of the root `README.md` first (structure, conventions). Every stage already has its scene
`game/scenes/levels/<stage>.tscn`, arranged by the user by hand: there is no generator any more. `git status` shows his uncommitted
edits - edit the file as text, keep them, and commit them together with your work.

## A. The stage scene

1. **Depth is the user's job**: do not move pieces between `Art/Far` (0.8), `Middle` (0.9) and `Near` (1.0) on your own. Only when he asks:
   convert x (x_layer = s * x_orig, back: x_orig = x_layer / s) and keep the painting order (far pieces first, then middle, then what was in front).
2. The sky picture is `Background` (CanvasLayer -2) / `Sky` (Sprite2D); `Level` scrolls it over the stage length from where the sprite stands.
3. Runs of identical pictures edge to edge (haze, floor) are ONE TextureRect: texture_repeat on, stretch Tile, **texture_filter Nearest**.
4. **Overlays**: leave the 4399 logo that is *embedded* in a texture alone - never scrub it. Bitmaps that are *only* the logo (83x36, alpha 0.17) and the
   grey "fake mist" strips along the ground are dropped by `tools/rig/drop_overlays.js` (keys per stage in `DROP`) when a stage is extracted anew; never
   put a dropped piece back on your own, and never decide anything else for the user.
5. **Mechanisms** (doors, switches...): a scene `scenes/objects/<name>.tscn` with a script on the root (`src/level/objects/<name>.gd`, `@export`
   parameters, a `Guides` node for editor-only boxes), instanced under `Objects/<Name>` at its **real world position** (from `game/data/stages.json`
   or the original's stage listener - NOT from level.json `doors`, which can be wrong). Built from plain Sprite2D nodes with a normal AnimationPlayer
   for what really animates; never a Rig (its parts are hidden until it plays). Its textures live next to the stage (`assets/levels/<stage>/tex`).
   Point `tools/stage_test.gd` at the node. Mechanisms get no parallax.
6. Wire the lighting file (section B) and README notes; commit on the `visual` branch.

Some stages are not pieces at all: 5-1 白骨精 is ONE finished 940x590 painting plus a floor strip. Do not try to cut it up; design the look for a
painted backdrop: light dimming/tint, no rim light or feet fade on it (`rim:0, fade:0` for its layer), mist/rain around it.

## B. Look design (data/lighting/<stage>.json -> src/level/stage_lighting.gd)

Methodology - decide the **mood in one sentence** per stage first, then express it with a fixed set of knobs, always in this order:
1. **Value structure**: dim scenery/ground/far (`scene.art/ground/far` multipliers, far a little lighter = aerial perspective), dim actors less (`body.shade/lit`),
   never dim pickups/numbers/HUD. Night is cool blue; other moods change the hue, not the pipeline.
2. **One light logic**: find the stage's own light source and make everything agree with it. The rim light (`rim_*`, `art_look.gdshader`, body rim
   `Rig.set_light`) and the moon glow / shafts exist **because 1-1..1-3 have a moon** - they are not a general setting. A new style is designed from scratch: ask what lights this place
   (a pillar of light from above, lava glow from below, lanterns, nothing) and set rim (`rim_strength 0` to switch it off), shadows (`shadow.shear/squash/blur/alpha`), lights
   (`lamps`, `glows`, `moon`) accordingly. No source (overcast) = drop `moon`, no rim.
3. **Depth**: fade decoration to dark at the feet (`fade_height/fade_dark`), per-layer tint/blur (`layers.Far.blur`, `tint`) - aerial perspective, slight DOF.
4. **Atmosphere**: mist (`fog.*`, shader-driven, never a baked strip), in front of the world; density scales the mood (1-1 heavy, 1-2 thin).
5. **Weather / particles** (differentiate stages by them): `rain`, `lightning`, `ash` (floating motes, bubbles, embers), `stars`, `sway` (smoke-like warp of flames).
   Escalate across a set of related stages: 1-1 moonlit mist -> 1-2 no moon, drizzle -> 1-3 darker, 2x rain, thunder; a new area gets its own mood.
6. **Grade**: `grade.saturation/vignette/brightness` last, a global pass over the world (under the HUD).

Rules learned the hard way: effects stay out of gameplay; nothing screen-fixed that should be world-fixed; weather has its own RNG (never the gameplay `Rng`);
the project is Forward+ with 2D MSAA; numbers live in the json, not the code; every effect is optional by key so a stage without it is untouched. Check with
`godot --path game --position 6000,6000 res://tools/light_shot.tscn -- <a,b> <out.png> <camera x> [monster ids] [wait s] [strike s]` and view the png.
Do not take screenshots to judge anti-aliasing - the user judges. Headless cameras do not follow a hero teleported far away: shoot the first screen or move the thing under test.

## C. Gotchas
- The user's mid-turn feedback usually corrects scope ("only far/near", "don't glue pieces", "interactive things get no parallax") - follow it literally.
- CRLF repo files: edit with the Edit tool or scripts that split on `\r\n`; shell heredocs eat backslashes (regexes!) - write JS/GDScript helpers with the Write tool.
- `class_name` scripts need `godot --headless --path game --import` before a headless run sees them; autoloads are missing under `-s` scripts, use a tiny scene runner instead.
- Texture uid mismatch after moving textures makes scenes "fail to load: missing dependency": `node tools/rig/fix_scene_uids.js --fix`.
- Delete = Recycle Bin (`bash tools/trash.sh <path>`), never rm. Answer the user in Simplified Chinese; report what was and was not verified.
- Tests: run targeted checks only for art work (`stage_test`, `ai_trace -- --check` when shared code changed).
