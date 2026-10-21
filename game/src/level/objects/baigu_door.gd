class_name BaiguDoor
extends Node2D
## The white-bone door of 1-2 (StageListener12). Its weak spot sits at a random place; hit it with enough new attacks and
## the door opens; then standing in the doorway long enough leads to 白骨精 (5-1).
## A scene of its own (scenes/objects/baigu_door.tscn) placed in the stage scene (Objects/BaiguDoor): the numbers are exports.
## Everything in "Guides" is for the editor only.

@export var hits := 3                                            ## attacks the weak spot takes
@export var weak_dx := Vector2(-200.0, 200.0)                    ## where the WeakSpot area may be, from the door (random in this range)
@export var weak_dy := Vector2(-70.0, -20.0)
@export var enter_time := 5.0                                    ## seconds in the doorway (EnterZone)
@export var destination := Vector2i(5, 1)                        ## stage entered


signal opened

var _hits_left := 0
var _bullet_hits := {}   ## [bullet id, its attack serial] already counted
var _last_serial := -1
var _open := false
var _enter_left := 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # keyed frames must not be smeared between physics ticks
	add_to_group(&"lit_scenery")   # the stage's lighting treats it as scenery
	$Guides.queue_free()
	$Opened.visible = false
	$WeakSpot.position = Vector2(Rng.randf_range(weak_dx.x, weak_dx.y), Rng.randf_range(weak_dy.x, weak_dy.y))
	_hits_left = hits
	_enter_left = enter_time

func is_open() -> bool:
	return _open

func hits_left() -> int:
	return _hits_left

## Where the weak spot is (it moves to a random place when the door is placed).
func weak_spot() -> Area2D:
	return $WeakSpot

func _physics_process(delta: float) -> void:
	var level := Level.current
	if level == null:
		return
	var hero := level.hero
	if not is_instance_valid(hero):
		return
	if not _open:
		if hero.dealer.serial != _last_serial and hero.hits($WeakSpot):
			_last_serial = hero.dealer.serial
			_take_hit()
		# the hero's bullets too (唐僧 attacks only with them): each attack of a bullet counts once
		for p in level.world.get_children():
			if _open:
				break
			if p is Projectile and p.source == hero and is_instance_valid(p.puppet):
				var key := [p.get_instance_id(), p.dealer.serial]
				if not _bullet_hits.has(key) and p.puppet.hitbox.overlaps_area($WeakSpot):
					_bullet_hits[key] = true
					_take_hit()
		return
	if hero.touches($EnterZone):
		_enter_left -= delta
		if _enter_left <= 0.0:
			level.go_to(destination)
	else:
		_enter_left = enter_time

func _take_hit() -> void:
	Fx.spawn("fx_monster_hurt1" if Rng.randf() < 0.5 else "fx_monster_hurt2", $WeakSpot.global_position)
	_hits_left -= 1
	if _hits_left <= 0:
		_open_door()

func _open_door() -> void:
	_open = true
	$Closed.visible = false
	$Opened.visible = true
	$Anim.play(&"open")
	opened.emit()

