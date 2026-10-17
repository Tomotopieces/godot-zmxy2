class_name HubStatue
extends Node2D
## The statue of the underworld hub (10-1, the original StageListener101): it stands in front of the hall art. When the
## selector's fifth place is picked and both stones were hit at nearly the same time, the stage script frees the selector
## and opens the statue: the closed statue is hidden, the open one shown and its "open" action plays; `open_time` seconds
## later the central slot ("colipse") may be entered (up there leads to 10-6).
## A scene of its own (scenes/objects/hub_statue.tscn) placed in the stage scene (Objects/HubStatue): the numbers are exports.

@export var open_time := 1.0                                  ## seconds until the slot may be entered (24 frames)
@export var enter_rect := Rect2(189.0, 17.1, 96.0, 506.0)     ## the central slot of the open statue

var ready_to_enter := false   ## the slot has opened: up inside enter_rect now enters 10-6

var _open := false

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # keyed frames must not be smeared between physics ticks
	add_to_group(&"lit_scenery")   # the stage's lighting treats it as scenery
	$Open.visible = false
	$Anim.animation_finished.connect(_on_anim_finished)

## The "open" action has a loop tail (the portal keeps turning): replay it from `loop_from` instead of stopping.
func _on_anim_finished(n: StringName) -> void:
	if n != &"open":
		return
	var an: Animation = $Anim.get_animation(&"open")
	if an != null and an.has_meta(&"loop_from"):
		$Anim.play(&"open")
		$Anim.seek(float(an.get_meta(&"loop_from")), true)

func is_open() -> bool:
	return _open

## Hide the closed statue, show the open one and play its "open" action; the slot opens `open_time` seconds later.
func open() -> void:
	if _open:
		return
	_open = true
	$Closed.visible = false
	$Open.visible = true
	$Anim.play(&"open")
	get_tree().create_timer(open_time, false).timeout.connect(func(): ready_to_enter = true)

func enter_world_rect() -> Rect2:
	return Rect2(global_position + enter_rect.position, enter_rect.size)
