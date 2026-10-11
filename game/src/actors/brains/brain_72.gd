extends MonsterBrain
## Monster72 都市王 (10-5 boss). hit3: rises in a flash and lands on the hero, then one of two slams; it can't be
## interrupted. Too many knockbacks force a hit3. Far: hit3 (cooldown) or chase; near, every check tick: hit2 net
## (heroes caught can't move or fall until the net goes; attacks and treasures still work, 血海魔童 frees) when ready, else hit1.

var _up_left := 10
var _net: Projectile

func setup() -> void:
	_up_left = int(param("up_hits", 10))

func think(delta: float) -> void:
	var tick := tick_check(delta)   # (the original's `count % 24`, free-running)
	if m.state != Monster.State.MOVE:
		return
	if _up_left <= 0:
		var r: Array = param("up_reset", [5, 10])
		_up_left = Rng.randi_range(r[0], r[1])
		m.face_target()
		act(&"hit3")
		return
	if not ensure_target(delta):
		return
	var d := m.to_target()
	if absf(d.x) > m.data.attack_range:
		if cooldown_ready("leap", float(param("leap_cd", 5.8))):
			m.face_target()
			act(&"hit3")
		else:
			follow()
		return
	m.dir = 0
	if tick:
		m.face_target()
		if cooldown_ready("net", float(param("net_cd", 10.8))):
			act(&"hit2")
		else:
			act(&"hit1")

func ignores_hit(_h: Hit) -> bool:
	return String(m.attack_action).begins_with("hit3")

func on_hurt_start() -> void:
	_up_left -= 1

func moves_while_attacking() -> bool:
	return m.attack_action == &"hit3"

func on_call(n: String, _args: Array) -> bool:
	match n:
		"create_light":
			Fx.spawn("monster72light2", m.global_position + Vector2(0, -100))
		"do_hit3":
			if m.target:
				m.global_position = Vector2(m.target.global_position.x, float(param("land_y", 430)))
				m.velocity = Vector2.ZERO
			act(&"hit3-1" if Rng.randf() < 0.5 else &"hit3-2")
		"do_hit2":
			_net = m.shoot("monster72bullet1", &"hit2", Vector2(150, 0))
			_net.attack = _net.attack.duplicate()
			_net.attack.effect_only = true   # the net does no damage, it only holds
			_net.life = float(param("net_life", 8.0))
			var lv := m.world
			_net.tree_exiting.connect(func():
				for h: Hero in lv.heroes():
					h.clear_debuff(&"net"))
		_:
			return false
	return true

func on_destroy() -> void:
	if is_instance_valid(_net):
		_net.queue_free()
	super()
