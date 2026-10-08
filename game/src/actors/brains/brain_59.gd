extends MonsterBrain
## Monster59 转轮王 form 1 (4-1): flies, hovering at a re-rolled offset from its target (turns at most once per its
## own interval). Every check tick: hit2 bomb rain when ready, else 50 % an aimed shot (hit1).
## Bombs explode where they reach the floor. On death it becomes form 2 (Monster51).

const SHOT := "monster59bullet1"
const BLAST := "monster59bullet2"

var _turn := 0.0
var _turn_every := 1.0
var _offset := Vector2(160, 140)
var _check := 0.0

func setup() -> void:
	m.fly = true
	var r: Array = param("turn_every", [1.0, 3.0])
	_turn_every = Rng.randf_range(r[0], r[1])

func think(delta: float) -> void:
	_turn = maxf(_turn - delta, 0.0)
	if m.state != Monster.State.MOVE:
		m.velocity.y = 0.0
		return
	if m.target == null:
		wander(delta)
		m.velocity.y = 0.0
		select_target()
		return
	var d := m.to_target()
	if absf(d.x) > _offset.x or absf(d.y + _offset.y) > float(param("hover_slack", 40)):
		_hover(delta)
	else:
		wander(delta)
	_check -= delta
	if _check <= 0.0:
		_check = float(param("check", 1.0))
		if m.cd("rain") <= 0.0:
			m.set_cd("rain", float(param("rain_cd", 15.0)))
			_stop_and_face()
			m.attack_with(&"hit2")
		elif Rng.randf() < 0.5:
			_stop_and_face()
			m.attack_with(&"hit1")

func _stop_and_face() -> void:
	m.velocity = Vector2.ZERO
	m.face_target()

func _hover(delta: float) -> void:
	if _turn <= 0.0:
		_turn = _turn_every
		follow()
		_offset = Vector2(160.0 + Rng.randf_range(-40, 40), 140.0 + Rng.randf_range(-60, 60))
	var want_y := m.target.global_position.y - _offset.y
	var a := float(param("hover_accel", 288)) * (1.0 if m.global_position.y < want_y else -1.0)
	var cap := float(param("hover_max", 96))
	m.velocity.y = clampf(m.velocity.y + a * delta, -cap, cap)

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit1":
			if m.target:
				var to := m.target.global_position - m.global_position
				var s := m.shoot(SHOT, &"hit1")
				s.velocity = to.normalized() * float(param("shot_speed", 240))
				s.distance_left = to.length() + 40.0
				s.rig.scale *= 0.5
		"do_hit2":
			var v := Vector2(Rng.randf_range(param("bomb_vx", [120, 1056])[0], param("bomb_vx", [120, 1056])[1]), Rng.randf_range(72, 168))
			var b := m.shoot(SHOT, &"hit2", Vector2.ZERO, v, 9999.0)
			b.accel = Vector2(float(param("bomb_ax", 576)) * m.facing, float(param("bomb_ay", 1152)))
			var floor_y := float(param("floor_y", 472))
			b.mover = func(p: Projectile, delta: float) -> void:
				p.velocity += p.accel * delta
				p.position += p.velocity * delta
				if p.global_position.y >= floor_y:
					m.shoot(BLAST, &"hit2").global_position = Vector2(p.global_position.x, floor_y)
					p.queue_free()
		_:
			return false
	return true

## Form 1 falls: form 2 takes over (no exit yet).
func on_destroy() -> void:
	var pos: Array = param("next_pos", [1700, 175])
	m.summon(51, Vector2(pos[0], pos[1]))
