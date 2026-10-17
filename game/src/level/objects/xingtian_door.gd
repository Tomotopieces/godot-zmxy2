class_name XingtianDoor
extends Node2D
## 刑天门 of 2-2 / 2-3 / 11-1 (the original StageListener22/23/111): only a hero carrying the 阎罗令 (yll) can use it.
## Touching its box for `touch_time` seconds (the time is not reset when stepping away) opens it: the closed door is
## hidden, the open one shown and its "open" animation plays. Once it has swung open, walking into the doorway uses up
## the key and leads to 刑天 (7-1).
## A scene of its own (scenes/objects/xingtian_door.tscn) placed in the stage scene
## (Objects/XingtianDoor): the numbers are exports.

@export var key := "yll"                                            ## the item the hero must carry
@export var can_open := true                                        ## false: the door is only the closed picture and never opens
@export var destination := Vector2i(7, 1)                           ## stage entered
@export var touch_time := 1.0                                       ## seconds in touch_box to open it
@export var touch_box := Rect2(-86.0, -142.6, 156.0, 354.0)         ## where the hero touches it
@export var enter_rect := Rect2(-148.0, -186.5, 296.0, 173.0)       ## the doorway once open

const HERO_BOUNDS_MARGIN := 3.0   ## the original tests the hero's whole display bounds, a few px larger than its hurt box

signal opened

var _touch_left := 0.0
var _open := false

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # keyed frames must not be smeared between physics ticks
	add_to_group(&"lit_scenery")   # the stage's lighting treats it as scenery
	# placed among the scenery (inside a layer of Art, as in 2-3) it keeps the stage's draw order and lighting there;
	# placed in Objects (in the world) it sits at the mechanism depth
	if not _in_scenery():
		z_index = Layers.Z_MECHANISM
	$Open.visible = false
	$Anim.animation_finished.connect(_on_anim_finished)
	_touch_left = touch_time
	_choose_open_door()

## True when this door is a piece of a stage's scenery (a descendant of Art), not a world object.
func _in_scenery() -> bool:
	var p := get_parent()
	while p != null:
		if p.name == &"Art":
			return true
		p = p.get_parent()
	return false

## A stage may hold several 刑天门 (2-2, 2-3): one Rng draw picks the door that can be opened, the others stay the
## closed picture. The first door of the parent by name does the picking and writes `can_open` on every sibling.
func _choose_open_door() -> void:
	if not can_open or get_parent() == null:
		return
	var siblings: Array[XingtianDoor] = []
	for c in get_parent().get_children():
		if c is XingtianDoor:
			siblings.append(c)
	if siblings.size() < 2:
		return
	siblings.sort_custom(func(a: XingtianDoor, b: XingtianDoor) -> bool: return a.name < b.name)
	if siblings[0] != self:
		return
	var chosen := Rng.randi_range(0, siblings.size() - 1)
	for i in siblings.size():
		siblings[i].can_open = i == chosen

## The closed door is gone, the open one plays its "open" action (once the rig has settled the hero may walk in).
func is_open() -> bool:
	return _open

func _physics_process(delta: float) -> void:
	var level := Level.current
	if level == null:
		return
	var hero := level.hero
	if not is_instance_valid(hero) or not GameState.has_item(key):
		return
	if not _open:
		if not can_open:
			return   # only the chosen door of a stage opens; the others never do
		if hero.is_alive() and touch_world_rect().intersects(hero.hurt_rect().grow(HERO_BOUNDS_MARGIN)):
			_touch_left -= delta
			if _touch_left <= 0.0:
				_open_door()
		return
	if not _settled():
		return   # the doorway opens once the door has swung open (the vortex then keeps turning)
	if hero.is_alive() and enter_world_rect().intersects(hero.hurt_rect().grow(HERO_BOUNDS_MARGIN)):
		if GameState.take_item(key):
			level.go_to(destination)

func touch_world_rect() -> Rect2:
	return Rect2(global_position + touch_box.position, touch_box.size)

func enter_world_rect() -> Rect2:
	return Rect2(global_position + enter_rect.position, enter_rect.size)

func _open_door() -> void:
	_open = true
	$Closed.visible = false
	$Open.visible = true
	$Anim.play(&"open")
	opened.emit()

## The "open" action has a loop tail (the vortex keeps turning): replay it from `loop_from` instead of stopping.
func _on_anim_finished(n: StringName) -> void:
	if n != &"open":
		return
	var an: Animation = $Anim.get_animation(&"open")
	if an != null and an.has_meta(&"loop_from"):
		$Anim.play(&"open")
		$Anim.seek(float(an.get_meta(&"loop_from")), true)

## The door has finished swinging open (the vortex underneath keeps turning).
func _settled() -> bool:
	var an: Animation = $Anim.get_animation(&"open")
	return an != null and an.has_meta(&"loop_from") and $Anim.current_animation_position >= float(an.get_meta(&"loop_from"))
