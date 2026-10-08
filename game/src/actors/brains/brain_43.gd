extends MonsterBrain
## Monster43, flyer (3-2 / 3-3): no gravity, hovers about `hover` px above its target, turning at most once per
## its own turn interval; attacks on the base cadence with three arcing shots; after attacking it climbs away.

const SHOT := "monster43bullet1"

var _turn := 0.0
var _turn_every := 1.0
var _back := 0.0

func setup() -> void:
	m.fly = true
	m.velocity = Vector2.ZERO
	var r: Array = param("turn_every", [1.0, 3.0])
	_turn_every = Rng.randf_range(r[0], r[1])

func think(delta: float) -> void:
	_turn = maxf(_turn - delta, 0.0)
	_back = maxf(_back - delta, 0.0)
	if m.state != Monster.State.MOVE:
		m.velocity.y = 0.0
		return
	if _back > 0.0:
		m.velocity.y = -float(param("climb", 72)) if m.global_position.y > float(param("climb_top", 150)) else 0.0
		return
	if m.target == null:
		wander(delta)
		m.velocity.y = 0.0
		select_target()
		return
	var d := m.to_target()
	if absf(d.x) > float(param("near_x", 180)) or absf(d.y) > float(param("near_y", 200)):
		_follow(delta)
	else:
		m.dir = 0
		_attack_t -= delta
		if _attack_t <= 0.0:
			_attack_t = m.data.attack_check
			if Rng.randi() % 100 < m.data.attack_chance:
				m.velocity = Vector2.ZERO
				attack()
				_back = float(param("back_time", 3.0))

## Turn toward the target at most once per turn interval; ease toward `hover` px above it.
func _follow(delta: float) -> void:
	if _turn <= 0.0:
		_turn = _turn_every
		follow()
	var want_y := m.target.global_position.y - float(param("hover", 200))
	var a := float(param("hover_accel", 288)) * (1.0 if m.global_position.y < want_y else -1.0)
	var cap := float(param("hover_max", 96))
	m.velocity.y = clampf(m.velocity.y + a * delta, -cap, cap)

func on_call(n: String, _args: Array) -> bool:
	if n != "do_hit1":
		return false
	var v := Vector2(float(param("shot_vx", 144)), -float(param("shot_vy", 96)))
	var g := Vector2(0, float(param("shot_gravity", 345)))
	for i in 3:
		var s := m.shoot(SHOT, &"hit1", Vector2((i - 1) * 30.0, 0), Vector2(v.x * (i - 1), v.y), float(param("shot_distance", 1000)))
		s.accel = g
	return true
