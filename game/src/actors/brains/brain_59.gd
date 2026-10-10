extends MonsterBrain
## Monster59 转轮王 form 1 (4-1): flies and hovers above its target. Bomb rain (15 s cooldown) or an aimed shot, checked once a second.
## Bombs explode where they reach the floor. On death it becomes form 2 (Monster51).


const SHOT := "monster59bullet1"
const BLAST := "monster59bullet2"

## Monster59 in the original: one counter `count` (seconds here) drives everything.
##  - the hero is followed (heading and height) while it is farther than the hover offset in x or y; heading is only
##    re-chosen once per `change_time` (fixed per boss, 1-3 s), and then the hover offset is re-rolled
##  - inside the offset it just coasts (normalWalk): at count 0.5 s it re-aims, at 3 or 4 s it stops sideways and the
##    counter restarts; its vertical speed is not touched meanwhile
##  - every full second of the counter (while not attacking): the bomb rain when its cooldown is ready, else 50 % an
##    aimed shot
var _count := 0.0
var _stop_time := 3.0
var _change_time := 2.0
var _change_left := 0.0
var _offset := Vector2(180, 200)

func setup() -> void:
	m.fly = true
	var r: Array = param("change_time", [1.0, 3.0])
	_change_time = Rng.randf_range(r[0], r[1])

func think(delta: float) -> void:
	if m.state != Monster.State.MOVE:
		m.velocity.y = 0.0 if m.state == Monster.State.ATTACK else m.velocity.y
		return
	var prev := _count
	_count += delta
	if _count > float(param("count_reset", 10.0)):
		_count = 0.0
	if _change_left > 0.0:
		_change_left += delta
		if _change_left >= _change_time:
			_change_left = 0.0
	if m.target == null:
		wander(delta)   # normalWalk without a target
		m.velocity.y = 0.0
		select_target()
		return
	var d := m.to_target()
	if absf(d.y) <= m.data.attack_range * 2.0:
		if absf(d.x) > _offset.x or absf(d.y) > _offset.y:
			_follow_target(delta)
		else:
			_coast(prev)
		if floorf(_count) != floorf(prev):
			if m.cd("rain") <= 0.0:
				m.set_cd("rain", float(param("rain_cd", 15.0)))
				m.attack_with(&"hit2")
			elif Rng.randf() < float(param("shot_chance", 0.5)):
				m.velocity = Vector2.ZERO
				m.face_target()
				m.attack_with(&"hit1")
	else:
		_coast(prev)

## followTarget: head for the hero (re-chosen once per change_time), and rise / sink to the hover height above it.
func _follow_target(delta: float) -> void:
	if m.target == null:
		return
	if _change_left == 0.0:
		_offset = Vector2(160.0 + Rng.randf_range(-40, 40), 140.0 + Rng.randf_range(-60, 60))
		m.dir = 1 if m.target.global_position.x > m.global_position.x else -1
		_change_left = 0.0001
	var a := float(param("hover_accel", 288)) * (1.0 if m.global_position.y < m.target.global_position.y - _offset.y else -1.0)
	var cap := float(param("hover_max", 96))
	m.velocity.y = clampf(m.velocity.y + a * delta, -cap, cap)

## normalWalk with a target: re-aim once per cycle, stop sideways at the end of it.
func _coast(prev: float) -> void:
	var half := float(param("reaim_at", 0.5))
	if prev < half and _count >= half:
		_follow_target(0.0)
		_stop_time = float(param("stop_a", 3.0)) if Rng.randf() < 0.5 else float(param("stop_b", 4.0))
	if _count >= _stop_time:
		m.dir = 0
		_count = 0.0

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
					if is_instance_valid(m):   # (a bomb can outlive the boss that dropped it)
						m.shoot(BLAST, &"hit2").global_position = Vector2(p.global_position.x, floor_y)
					p.queue_free()
		_:
			return false
	return true

## Form 1 falls: form 2 takes over (no exit yet).
func on_destroy() -> void:
	var pos: Array = param("next_pos", [1700, 175])
	m.summon(51, Vector2(pos[0], pos[1]))
