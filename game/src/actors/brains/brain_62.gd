extends MonsterBrain
## Monster62, 楚江王's leech: leaps (hit1) and latches onto a hero within reach: rides on them, draining HP and
## healing its master on a tick, then lets go. When its master dies it sacrifices itself (reburn) to revive him.

var _host: Hero
var _ticks := 0
var _tick_t := 0.0
var _master: Monster

func setup() -> void:
	_master = m.summoner

func think(delta: float) -> void:
	if _host != null:
		_ride(delta)
		return
	if m.attack_action == &"reburn":
		return
	super(delta)

func _ride(delta: float) -> void:
	if not is_instance_valid(_host) or not _host.is_alive():
		_release()
		return
	m.global_position = _host.global_position + Vector2(0, -30)
	m.velocity = Vector2.ZERO
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = float(param("drain_every", 1.0))
		_host.lose_hp(int(param("drain", 100)))
		if is_instance_valid(_master):
			_master.heal(int(param("feed", 1000)))
		_ticks += 1
		if _ticks >= int(param("drain_ticks", 10)):
			_release()

func _release() -> void:
	_host = null
	m.fly = false
	m.invuln = float(param("release_invuln", 0.4))
	m.state = Monster.State.MOVE

func moves_while_attacking() -> bool:
	return m.attack_action == &"hit1"

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit1":
			for h: Hero in Level.current.heroes():
				if h.can_be_hit() and h.center().distance_to(m.center()) < float(param("latch_range", 100)):
					_host = h
					_ticks = 0
					_tick_t = float(param("drain_every", 1.0))
					m.invuln = 9999.0
					m.fly = true
					m.play_action(&"fixed")
					return true
		"do_re_burn":
			if is_instance_valid(_master):
				(_master.brain as Object).call("revive_at", m.global_position)
			m.invuln = 0.0
			m.damage_directly(999999)
		_:
			return false
	return true

## Master died: let go and sacrifice.
func go_reburn(master: Monster) -> void:
	_master = master
	_host = null
	m.fly = false
	m.invuln = float(param("reburn_invuln", 2.0))
	m.play_action(&"reburn")
