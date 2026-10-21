class_name AuroraGate
extends Node2D
## The aurora of 3-1 (StageListener31's AuroraLight): a permanent gate hanging over the water. A hero carrying the 避水珠
## (bsz) who touches its glow dives to 楚江王 (8-1).
## A scene of its own (scenes/objects/aurora_gate.tscn) placed in the stage scene (Objects/AuroraGate) at the point the
## original put it (1000, 600): the numbers are exports. The glow the hero touches is the GlowZone area.

@export var key := "bsz"                    ## the item the hero must carry
@export var destination := Vector2i(8, 1)   ## stage entered


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # keyed frames must not be smeared between physics ticks
	z_index = Layers.Z_AURORA
	var actions: PackedStringArray = $Anim.get_animation_list()
	if actions.size() > 0:
		$Anim.play(actions[0])


func _physics_process(_delta: float) -> void:
	var level := Level.current
	if level == null:
		return
	var hero := level.hero
	if is_instance_valid(hero) and hero.touches($GlowZone) and GameState.take_item(key):
		level.go_to(destination)
