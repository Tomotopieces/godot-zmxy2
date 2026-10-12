# Hand-made stage scenery

A stage with a scene here (`<stage>.tscn`: `sl11.tscn` = 1-1 鬼城, `sl12.tscn` = 1-2 无常巷, `sl13.tscn` = 1-3 鬼门关) takes its scenery from it instead of from
the `art` list of `assets/levels/<stage>/level.json`. Walls, camera stops, spawners and the exit still come from `level.json`; the far
sky picture (`far` in level.json) and the stage's lighting (`data/lighting/<stage>.json`) are separate too.

The tool `game/tools/level_to_scene.gd` makes the scene from level.json once (it never overwrites without `--force`):

    godot --headless --path game res://tools/level_to_scene.tscn -- sl12 [--force] [--far=1_v6:35] [--fog=1_v6:45,1_v6:60] [--near=1_v6:50]

## Structure

- `Scenery`
  - `Guides` - reference lines for the editor only (the floor, the first screen); the game drops them
  - `Art` - everything behind the actors
    - `Far` - a `Parallax2D`, scroll scale 0.8: distant silhouettes (`--far`)
    - `Fog`, `Fog2`... - `TextureRect`s straight under `Art`, at the speed of the ground: haze bands the length of the stage (`--fog`)
    - `Middle` - a `Parallax2D`, 0.9: the decoration
    - `Near` - a `Parallax2D`, 1.0: what the player passes close by (tall pieces around a door, and `--near`)
    - ...any other `Node2D` / `Parallax2D` you add: add its settings under `layers` in the lighting file (blur, tint, rim, fade)
  - `Ground` - the floor

Every picture the original placed is its own `Sprite2D`, named after its bitmap (`b47_03` = bitmap 47, the 3rd in painting order);
nothing is merged, so trees, houses and the gate can each be moved, deleted or sent to another layer.

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
