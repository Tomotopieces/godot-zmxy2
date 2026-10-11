extends MonsterBrain
## Monster56 夜叉 (3-2 boss). Phase 1: base AI. At 80 % HP it transforms (hit2) into an invisible runner:
## no knockback, runs at speed and turns toward a hero every few seconds; body contact hurts ("run" attack);
## when a hero is close it leaps (hit3) and slams, healing itself for each hero the slam hits.

const SLAM := "monster56bullet1"

var _phase2 := false
var _transforming := false
var _turn := 0.0
var _rehit := 0.0

func think(delta: float) -> void:
	if not _phase2:
		if not _transforming and float(m.hp) / m.max_hp <= float(param("transform_at", 0.8)) \
				and m.state != Monster.State.DEAD:
			_transforming = true
			m.invuln = float(param("transform_invuln", 2.0))
			m.attack_with(&"hit2")
			return
		super(delta)
		return
	if m.state == Monster.State.DEAD or m.attack_action == &"hit3":
		return
	m.super_armor = true
	_turn -= delta
	_rehit -= delta
	if _rehit <= 0.0:
		_rehit = float(param("run_rehit", 2.0))
		m.dealer.new_serial()
	if _turn <= 0.0:
		var r: Array = param("turn_every", [1.0, 3.0])
		_turn = Rng.randf_range(r[0], r[1])
		var h: Hero = m.world.hero
		if h:
			m.face(h.global_position)
	var near := false
	for h: Hero in m.world.heroes():
		if h.global_position.distance_to(m.global_position) < float(param("leap_range", 200)):
			near = true
	if near and m.cd("leap") <= 0.0:
		var r2: Array = param("leap_cd", [6.0, 10.0])
		m.set_cd("leap", Rng.randf_range(r2[0], r2[1]))
		m.attack_with(&"hit3")
		return
	# running is itself the attack: keep the run hitbox live
	if m.attack_action != &"run":
		m.state = Monster.State.ATTACK
		m.start_attack(&"run", m.data.attacks.get(&"run"))
	m.velocity.x = m.facing * float(param("run_speed", 240))

func moves_while_attacking() -> bool:
	return _phase2

func on_action_finished(action: StringName) -> void:
	if action == &"hit2":
		_phase2 = true
		m.modulate.a = float(param("phase2_alpha", 0.0))

func on_call(n: String, _args: Array) -> bool:
	if n != "do_hit3":
		return false
	var b := m.shoot(SLAM, &"hit3")
	b.on_hit = m.owned(func(_t: Actor) -> void:
		m.heal(int((m.max_hp - m.hp) * float(param("slam_heal", 0.05)))))
	return true

func custom_animation() -> bool:
	return _phase2
