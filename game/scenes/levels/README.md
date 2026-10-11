# Hand-made stage scenery

A stage with a scene here (`<stage>.tscn`, e.g. `sl11.tscn` = 1-1 鬼城) takes its scenery from it instead of from the `art` list of
`assets/levels/<stage>/level.json`. Walls, camera stops, spawners and the exit still come from `level.json`; the far sky picture
(`far` in level.json) and the stage's lighting (`data/lighting/<stage>.json`) are separate too.

Structure (the tool `game/tools/level_to_scene.gd` makes it from level.json once; it never overwrites without `--force`):

- `Scenery`
  - `Guides` - reference lines for the editor only (the floor, the first screen); the game drops them
  - `Art` - everything behind the actors
    - `Far` - a `Parallax2D` that scrolls at 0.6 of the camera: the distant layer (empty to start with)
    - `Near` - a `Parallax2D` at 1.0: the scenery as the original painted it
    - ...any other `Node2D` / `Parallax2D` you add: add its settings under `layers` in the lighting file (blur, tint, rim, fade)
  - `Ground` - the floor

Work in the 2D editor: drag a `Sprite2D` between layers, change a layer's `Scroll Scale`, add pictures. An object is placed where it
appears when the camera is at the start of the stage (the green frame in `Guides`); a layer with scroll scale below 1 drifts slower
than the ground as the camera moves (it is shifted by the camera's distance from the start). A layer that should pass in front of the
actors needs a higher `z_index` (the actors are at 0, effects 3; the stage's lighting sits above).
