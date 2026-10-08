extends Treasure
## 白霜镜 (Mirror): 邪灵寄生. Flies to the nearest enemy, drains a share of the hero's max HP from it every tick
## (ignores defence) for a while or until it dies, then flies back and heals the hero by everything drained.
## No target in reach: nothing happens and no MP is spent.

enum Phase { GO, DRAIN, BACK }

var _target: Monster
var _phase := Phase.GO
var _speed := 0.0
var _left := 0.0
var _tick_t := 0.0
var _total := 0
var _blood: Rig

func can_use() -> bool:
	_target = null
	var best: float = p.search
	for m in candidates():
		var d: float = m.global_position.distance_to(hero.global_position)
		if d <= best:
			best = d
			_target = m
	return _target != null

func begin() -> void:
	rig.play(&"hit1", true)
	_phase = Phase.GO
	_speed = p.start_speed
	_total = 0

func step(delta: float) -> void:
	if not using:
		return
	match _phase:
		Phase.GO:
			if not is_instance_valid(_target) or not _target.is_alive():
				_phase = Phase.BACK
			elif _fly_to(_target.global_position, delta):
				_phase = Phase.DRAIN
				_left = p.drain
				_tick_t = 0.0
				_speed = p.start_speed
				_drain()
		Phase.DRAIN:
			if not is_instance_valid(_target) or not _target.is_alive():
				_stop_drain()
				return
			global_position = _target.global_position + Vector2(0, p.y_offset)
			_left -= delta
			_tick_t += delta
			if _tick_t >= p.tick:
				_tick_t -= p.tick
				_drain()
			if _left <= 0.0:
				_stop_drain()
		Phase.BACK:
			if _fly_to(hero.global_position, delta):
				hero.heal(_total)
				_total = 0
				finish()

## Accelerating flight; true on arrival.
func _fly_to(pos: Vector2, delta: float) -> bool:
	var to := pos - global_position
	_speed = minf(_speed + p.speed_step * delta, p.max_speed)
	if to.length() <= maxf(p.reach, _speed * delta):
		global_position = pos
		return true
	global_position += to.normalized() * _speed * delta
	return false

func _drain() -> void:
	var dmg := maxi(1, int((p.pct_base + p.pct_per_level * level()) * hero.max_hp * element_mul("mul")))
	_target.target = hero
	_target.hurt_directly(dmg)
	_total += dmg
	if _blood == null:
		_blood = Rig.create("fabao_mirror_blood")
		add_child(_blood)
		_blood.play(_blood.actions[0])
		_blood.action_finished.connect(func(a): _blood.play(a, true))

func _stop_drain() -> void:
	if _blood:
		_blood.queue_free()
		_blood = null
	_target = null
	_phase = Phase.BACK
