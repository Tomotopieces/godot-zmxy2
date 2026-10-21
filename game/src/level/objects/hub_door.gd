class_name HubDoor
extends Node2D
## A door of the underworld hub (10-1, the original StageListener101.TransferDoor). The closed door shows through an arch
## of the hall art; once the selector points at its place and both stones were hit at nearly the same time, the stage
## script opens it: the closed door is hidden, the open one shown and its "open" action plays; `open_time` seconds later
## the doorway may be entered (up there leads to 10-(2 + index)).
## A scene of its own (scenes/objects/hub_door.tscn) placed in the stage scene (Objects/HubDoor1 .. Objects/HubDoor4):
## index is its place on the selector, the rest are exports.

@export var index := 0                                          ## its place on the selector (0-based)
@export var open_time := 0.666666666666667                      ## seconds until the doorway may be entered (16 frames)

var ready_to_enter := false   ## the door has swung open: up inside EnterZone now enters the stage behind it

var _open := false

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # keyed frames must not be smeared between physics ticks
	add_to_group(&"lit_scenery")   # the stage's lighting treats it as scenery
	$Open.visible = false
	$Anim.animation_set_next(&"open", &"open_loop")   # the portal keeps turning once it has opened


func is_open() -> bool:
	return _open

## Hide the closed door, show the open one and play its "open" action; the doorway opens `open_time` seconds later.
func open() -> void:
	if _open:
		return
	_open = true
	$Closed.visible = false
	$Open.visible = true
	$Anim.play(&"open")
	get_tree().create_timer(open_time, false).timeout.connect(func(): ready_to_enter = true)

## The hero stands in EnterZone (the doorway of the open door).
func hero_inside(hero: Hero) -> bool:
	return hero.touches($EnterZone)
