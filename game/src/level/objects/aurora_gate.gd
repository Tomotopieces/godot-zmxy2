class_name AuroraGate
extends Node2D
## The aurora of 3-1 (StageListener31's AuroraLight): a permanent gate hanging over the water. A hero carrying the 避水珠
## (bsz) who touches its glow dives to 楚江王 (8-1).
## A scene of its own (scenes/objects/aurora_gate.tscn, built by tools/rig_to_object.gd) placed in the stage scene
## (Objects/AuroraGate) at the point the original put it (1000, 600): the numbers are exports.
## The gameplay rectangle is the rig's hit box, stored on the root as the `hit_rect_glow` meta (moved by the node's
## position), since the glow has no Hitbox of its own any more.

@export var key := "bsz"                    ## the item the hero must carry
@export var destination := Vector2i(8, 1)   ## stage entered

const HERO_BOUNDS_MARGIN := 3.0   ## the original tests the hero's whole display bounds, a few px larger than its hurt box

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # keyed frames must not be smeared between physics ticks
	z_index = Layers.Z_AURORA
	var actions: PackedStringArray = $Anim.get_animation_list()
	if actions.size() > 0:
		$Anim.play(actions[0])

## Where the glow is, in world space.
func glow_rect() -> Rect2:
	var box: Rect2 = get_meta("hit_rect_glow", Rect2())
	return Rect2(global_position + box.position, box.size)

func _physics_process(_delta: float) -> void:
	var level := Level.current
	if level == null:
		return
	var hero := level.hero
	if not is_instance_valid(hero) or not hero.is_alive():
		return
	var r := glow_rect()
	if r.size != Vector2.ZERO and r.intersects(hero.hurt_rect().grow(HERO_BOUNDS_MARGIN)) and GameState.take_item(key):
		level.go_to(destination)
