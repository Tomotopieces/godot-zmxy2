# Hand-made stage scenery

Every stage has a scene here (every stage has one, `<stage>.tscn`: `sl11` = 1-1 鬼城, `sl12` = 1-2 无常巷, `sl13` = 1-3 鬼门关, `sl21` = 2-1 接引院, `sl51` = 5-1 白骨精, ..., `sl01` = the debug arena); it takes its scenery from it instead of from
the `art` list of `assets/levels/<stage>/level.json`. Walls, camera stops, spawners and the exit still come from `level.json`; the
stage's lighting (`data/lighting/<stage>.json`) are separate too.

The tool `game/tools/level_to_scene.gd` makes the scene from level.json once (it never overwrites without `--force`):

    godot --headless --path game res://tools/level_to_scene.tscn -- sl21

## Structure

- `Scenery`
  - `Guides` - reference lines for the editor only (the floor, the first screen); the game drops them
  - `Background/Sky` - a `CanvasLayer` (-2) with the sky picture; Level scrolls it over the length of the stage, starting from where the sprite stands
  - `Art` - everything behind the actors
    - `Far` - a `Parallax2D`, scroll scale 0.8
    - `Middle` - a `Parallax2D`, 0.9
    - `Near` - a `Parallax2D`, 1.0: **every piece starts here**, at its original x. The generated scene has `Far` and `Middle` empty: the layering is yours.
    - ...any other `Node2D` / `Parallax2D` / `TextureRect` you add: add its settings under `layers` in the lighting file (blur, tint, rim, fade)
  - `Ground` - the floor (one tiling `TextureRect`)

Every picture the original placed is its own `Sprite2D`, named after its bitmap (`2_624_05` = bitmap 624, the 5th piece in painting order);
nothing is merged. Bitmaps that are only the 4399 logo or only a fake-mist strip were left out; a logo embedded in a texture is untouched.

## Layers and positions

A `Parallax2D` at scroll scale `s` moves with `s` of the camera. What it holds is placed at `s *` the original x (a piece that is
1000 px along the stage in the original is at x = 900 in `Middle`): with the camera at the piece, it is where the original had it,
and the further the camera is from it the slower it slides. When you move a piece to another layer, multiply or divide its x by
the layers' ratio (0.8 / 0.9 / 1.0). The y scale stays 1 (the camera never moves vertically).

## Repeating pictures

A row of the same picture laid side by side (haze, floor) is **one `TextureRect`** with `Texture Repeat` on, `Stretch Mode` =
Tile and **`Texture Filter` = Nearest** (linear filtering blends the tile edges and brings the seams back) (the tool makes them; a run of 3+ pieces that touch edge to edge). Resize the rect to cover more or less: no seams, no node
per tile. Do the same by hand for anything that repeats.

## Editing

Work in the 2D editor: drag a node between layers, change a layer's scroll scale, add pictures. A layer that should pass in front of
the actors needs a higher `z_index` (the actors are at 0, effects 3; the stage's lighting sits above).

Textures live next to their level (`assets/levels/<stage>/tex/<library>_<id>.png`, the library and symbol id of the original SWF);
the ones several levels use are in `assets/shared/levels/`.

## Mechanisms (`Objects`)

A stage's working objects are scenes of their own, instanced under `Scenery/Objects`; each has its script on its root node and its
numbers as exports (select the node: the Inspector shows them). Level moves `Objects` into the world as it is when the stage starts.
Positions are world positions (no parallax, like `Near` at 1.0).

- `scenes/objects/baigu_door.tscn` (script `src/level/objects/baigu_door.gd`, `BaiguDoor`) - the white-bone door of 1-2, at (2270, 336),
  the middle of the third screen. `Closed` is its picture; `Opened` (hidden) and the `open` animation are what it turns into. The
  yellow and blue boxes under `Guides` are for the editor only (where the weak spot may be; the doorway to stand in once open). Exports:
  hits, weak spot size / range, doorway, seconds in it, the stage it leads to. `level_to_scene.gd` does not make `Objects`: re-making a
  stage's scene with `--force` would drop them, add them again by hand.
- `scenes/objects/boat.tscn` (script `src/level/objects/boat.gd`, `Boat`) - the boat of 3-1, at its start (272.35, 495): an `AnimatableBody2D` with the deck's collision shape and the boat's pictures
  (plain `Hull` and `Water` Sprite2Ds; the ripple is an `Anim` animation of `Water`, not a rig). It sails by itself (exports: speed, where it ties up, the bob table) and emits `arrived`; `stages/sl31.gd` hangs the soldiers and fish on it and opens the exit.

## Stages whose background was baked by the original (sl22)

2-2 (sl22) has its background as ONE 4700x522 JPEG (bitmap 605, apparently a screenshot of the design) instead of loose bitmaps. It was rebuilt from the loose bitmaps of 2-3
(sl23, the same art set) by template matching: the brick wall, header, railing, doors, pillars, statues and chains are the artist's bitmaps again, placed where the
baked picture shows them (positions are inferred: pitch 446 for the wall, 222 for the railing, 443.5 for the header; the rest matched one by one). The last part (from x=3745: the
boss end with the chandelier, which exists only inside the baked picture) stays a crop of the baked bitmap (`2_605_boss`). Small gaps and tone differences are expected.
