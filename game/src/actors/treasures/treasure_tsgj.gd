extends Treasure
## 天煞古剑 (Sword): 御剑飞行. The sword flies forward as a one-way platform, slows down and comes back
## (boomerang); its blade hurts enemies while it flies. Once the hero stands on it, it stops (dips a little)
## and only serves as a platform. Gone after its life; then the treasure shows again.

var _body: AnimatableBody2D
var _art: Rig
var _blade: Projectile
var _vx := 0.0
var _dir := 1
var _age := 0.0
var _stand_t := 0.0
var _stopped := false

func begin() -> void:
	visible = false
	_dir = hero.facing
	_vx = p.speed * _dir
	_age = 0.0
	_stand_t = 0.0
	_stopped = false
	_body = AnimatableBody2D.new()
	_body.sync_to_physics = false
	_body.collision_layer = Actor.LAYER_ONEWAY
	_body.collision_mask = 0
	_art = Rig.create("fabao_sword_platform")
	_art.visible = false
	_body.add_child(_art)
	var r := _art_rect()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(r.size.x, 8)
	cs.shape = shape
	cs.position = Vector2(r.get_center().x, r.position.y + 4)
	cs.one_way_collision = true
	_body.add_child(cs)
	_body.global_position = hero.global_position
	world.add_object(_body)
	_art.play(_art.actions[0])
	_blade = shoot("fabao_sword_effect", &"fabao_sword", _body.global_position, -_dir, flat_roll(p.damage, p.per_level, p.spread))

## Bounds of the platform art in its own space.
func _art_rect() -> Rect2:
	var r := Rect2()
	for sp: Sprite2D in _art.find_children("*", "Sprite2D", true, false):
		var sr := _art.global_transform.affine_inverse() * sp.global_transform * sp.get_rect()
		r = sr if r.size == Vector2.ZERO else r.merge(sr)
	return r

func follows() -> bool:
	return true

func step(delta: float) -> void:
	if not using or not is_instance_valid(_body):
		return
	_age += delta
	if not _stopped:
		if _hero_on_it():
			_stop()
		else:
			_vx -= _dir * p.decel * delta
			_body.position.x += _vx * delta
			var face := 1 if _vx > 0.0 else -1
			_art.scale.x = face
			if is_instance_valid(_blade):
				_blade.global_position = _body.global_position
				if _blade.facing != -face:
					_blade.facing = -face
					_blade.dealer.new_serial()
	else:
		_stand_t += delta
	if _stand_t >= p.stand_life or _age >= p.life:
		_end()

func _hero_on_it() -> bool:
	if not hero.is_on_floor():
		return false
	for i in hero.get_slide_collision_count():
		if hero.get_slide_collision(i).get_collider() == _body:
			return true
	return false

func _stop() -> void:
	_stopped = true
	if is_instance_valid(_blade):
		_blade.queue_free()
	_art.visible = true
	var y := _body.position.y
	var tw := _body.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(_body, "position:y", y + p.sink, p.sink_time)
	tw.tween_property(_body, "position:y", y + p.sink - p.rise, p.rise_time)

func _end() -> void:
	if is_instance_valid(_blade):
		_blade.queue_free()
	if is_instance_valid(_body):
		_body.queue_free()
	visible = true
	finish()

func _exit_tree() -> void:   # taken off while the sword is out: it goes with it
	if is_instance_valid(_blade):
		_blade.queue_free()
	if is_instance_valid(_body):
		_body.queue_free()
