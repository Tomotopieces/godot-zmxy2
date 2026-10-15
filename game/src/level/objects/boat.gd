class_name Boat
extends AnimatableBody2D
## The boat of 3-1 (export.Boat, driven by StageListener31): a platform that sails right with a gentle bob and stops at the far
## pier, where the exit opens. A scene of its own (scenes/objects/boat.tscn) placed in the stage scene (Objects/Boat): the numbers are
## exports; the hull is a plain Sprite2D. Its own water ripple was removed (the stage's RiverWater covers the water line:
## src/level/water.gdshader); the stage script (stages/sl31.gd) hangs the soldiers and fish on it and opens the exit on `arrived`.

@export var speed := 48.0                   ## px / s to the right
@export var stop_x := 4129.0                ## where it ties up
@export var bob_step := 1.0 / 24.0          ## seconds per entry of the bob table (one original frame)
@export var bob := PackedFloat32Array([0.95, 0.9, 0.85, 0.75, 0.65, 0.55, 0.5, 0.45, 0.4, 0.35, 0.3, 0.25, 0.2, 0.15, 0.1, 0.15, 0.1, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0])
## y moves by the table downwards, then back up (ObsWall speedY)

signal arrived

var sailing := true
var _bob_t := 0.0
var _bob_i := 0
var _bob_dir := 1.0

func _ready() -> void:
	collision_layer = Actor.LAYER_WORLD
	collision_mask = 0
	sync_to_physics = false             # moved directly in the physics step
	process_physics_priority = 5        # after the level and the actors, as the stage script used to be
	z_index = Layers.Z_PICKUP           # drawn over whoever stands on it (its rail and water cover their feet)

## Half of the deck's width.
func half_width() -> float:
	return (($Shape as CollisionShape2D).shape as RectangleShape2D).size.x / 2.0

func _physics_process(delta: float) -> void:
	if not sailing:
		return
	position.x += speed * delta
	_bob_t += delta
	while _bob_t >= bob_step and not bob.is_empty():
		_bob_t -= bob_step
		position.y += bob[_bob_i] * _bob_dir
		_bob_i += 1
		if _bob_i >= bob.size():
			_bob_i = 0
			_bob_dir = -_bob_dir
	if position.x >= stop_x:
		sailing = false
		arrived.emit()
