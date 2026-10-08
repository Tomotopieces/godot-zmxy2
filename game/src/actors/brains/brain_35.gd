extends "res://src/actors/brains/boss_b.gd"
## Monster35, the 秦广王傀儡's puppet (1-3). Template B: far -> hit3 (four stabs from the top of the screen),
## near -> grab (hit2-1 then hit2-2). A grabbed hero is frozen and pulled until the grab ends or 35 is hurt.

const STAB_RIG := "monster35bullet1"

var _held: Array[Hero] = []

func far_skill(action: StringName) -> void:
	m.attack_with(action)

## releSkill2 / attackTarget both open the grab: invulnerable for its wind-up.
func near_skill(action: StringName) -> void:
	m.invuln = maxf(m.invuln, float(param("grab_invuln", 1.0)))
	m.attack_with(action)

func attack(_action: StringName = &"hit1") -> void:
	m.face_target()
	m.attack_with(&"hit2-1")

func on_action_finished(action: StringName) -> void:
	if action == &"hit2-1":
		m.attack_with(&"hit2-2")   # hit2-1 frame 26 switches to the pulling hit2-2

func on_hit_hero(hero: Hero, action: StringName) -> void:
	if action == &"hit2-1" or action == &"hit2-2":
		hero.held_by = m
		if not _held.has(hero):
			_held.append(hero)

func on_call(n: String, _args: Array) -> bool:
	match n:
		"remove_all_tielian_object":
			_release()
		"do_hit3":
			_stabs()
		_:
			return false
	return true

func on_hurt_start() -> void:
	_release()

func on_destroy() -> void:
	_release()
	super()

func _release() -> void:
	for h in _held:
		if is_instance_valid(h) and h.held_by == m:
			h.held_by = null
	_held.clear()

## doHit3: four stabs along the top of the scene at x-100 .. x+50; each turns toward where the target
## was over turn time, then flies at it with growing speed.
func _stabs() -> void:
	if m.target == null:
		return
	var aim := m.target.global_position
	for i in 4:
		var start := Vector2(m.global_position.x + (i - 2) * float(param("stab_spacing", 50)), 0)
		var s := m.shoot(STAB_RIG, &"hit3")
		s.global_position = start
		s.life = float(param("stab_life", 10.0))
		s.modulate.a = 0.0
		var heading := (aim - start).normalized()
		var turn := float(param("stab_turn", 1.0))
		var tw := s.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
		tw.tween_property(s, "modulate:a", 1.0, turn)
		tw.tween_property(s.rig, "rotation", heading.angle() - PI / 2.0, turn)
		var v0 := float(param("stab_speed", 24.0))
		var jerk := float(param("stab_jerk", 690.0))
		s.mover = func(p: Projectile, delta: float) -> void:
			if p.age < turn:
				return
			var t := p.age - turn
			p.position += heading * (v0 + 0.5 * jerk * t * t) * delta
			if absf(p.position.y) > 1000.0:
				p.queue_free()
