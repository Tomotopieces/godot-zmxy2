class_name BaiguDoor
extends Node2D
## The white-bone door of 1-2 (StageListener12). Its weak spot sits at a random place; hit it with enough new attacks and
## the door opens; then standing in the doorway long enough leads to 白骨精 (5-1).
## A scene of its own (scenes/objects/baigu_door.tscn) placed in the stage scene (Objects/BaiguDoor): the numbers are exports.
## Everything in "Guides" is for the editor only.

@export var hits := 3                                            ## attacks the weak spot takes
@export var weak_box := Rect2(-20.5, -20.5, 41, 41)              ## the weak spot, around its place
@export var weak_dx := Vector2(-200.0, 200.0)                    ## where its place may be, from the door (random in this range)
@export var weak_dy := Vector2(-70.0, -20.0)
@export var enter_rect := Rect2(-106.0, -8.1, 174.0, 101.0)      ## the doorway once open
@export var enter_time := 5.0                                    ## seconds in the doorway
@export var destination := Vector2i(5, 1)                        ## stage entered

const HERO_BOUNDS_MARGIN := 3.0   ## the original tests the hero's whole display bounds, a few px larger than its hurt box

signal opened

var _weak_at := Vector2()   ## where the weak spot is, from the door
var _hits_left := 0
var _last_serial := -1
var _open := false
var _enter_left := 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # keyed frames must not be smeared between physics ticks
	add_to_group(&"lit_scenery")   # the stage's lighting treats it as scenery
	$Guides.queue_free()
	$Opened.visible = false
	_weak_at = Vector2(Rng.randf_range(weak_dx.x, weak_dx.y), Rng.randf_range(weak_dy.x, weak_dy.y))
	_hits_left = hits
	_enter_left = enter_time

func is_open() -> bool:
	return _open

func hits_left() -> int:
	return _hits_left

func weak_rect() -> Rect2:
	return Rect2(global_position + _weak_at + weak_box.position, weak_box.size)

func enter_world_rect() -> Rect2:
	return Rect2(global_position + enter_rect.position, enter_rect.size)

func _physics_process(delta: float) -> void:
	var level := Level.current
	if level == null:
		return
	var hero := level.hero
	if not is_instance_valid(hero):
		return
	if not _open:
		if hero.dealer.serial != _last_serial and _hero_hits(hero, weak_rect()):
			_last_serial = hero.dealer.serial
			Fx.spawn("fx_monster_hurt1" if Rng.randf() < 0.5 else "fx_monster_hurt2", weak_rect().get_center())
			_hits_left -= 1
			if _hits_left <= 0:
				_open_door()
		return
	if hero.is_alive() and enter_world_rect().intersects(hero.hurt_rect().grow(HERO_BOUNDS_MARGIN)):
		_enter_left -= delta
		if _enter_left <= 0.0:
			level.go_to(destination)
	else:
		_enter_left = enter_time

func _open_door() -> void:
	_open = true
	$Closed.visible = false
	$Opened.visible = true
	$Anim.play(&"open")
	opened.emit()

## The hero's current attack box touches `r` (the stick test of the original doors).
func _hero_hits(hero: Hero, r: Rect2) -> bool:
	if hero.attack == null:
		return false
	var hr := hero.rig.hit_rect()
	return hr.size != Vector2.ZERO and hr.intersects(r)
