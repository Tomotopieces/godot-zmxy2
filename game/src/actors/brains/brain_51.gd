extends "res://src/actors/brains/boss_b.gd"
## Monster51 转轮王 form 2 (4-1), template B (range 400). Far: hit3 melee spin; near: hit2 burst (cooldown) or hit1.
## hit1 throws a ring at the target that stays where it lands as a trap (6 rings); with all six out, the next hit1
## pulls every ring back to the boss. On death it becomes form 3 (Monster60).

const RING := "monster51bullet1"
const BURST := "monster51bullet3"

var _rings: Array[Projectile] = []

func setup() -> void:
	_show_rounds()

## The ring counter on the body: frame = 7 - rings left (Monster51.getRoundValue); the rings in it keep turning.
func _show_rounds() -> void:
	if m.puppet == null:
		return
	m.puppet.set_equip("round", _rings.size() + 1)

func near_skill(action: StringName) -> void:
	m.invuln = maxf(m.invuln, float(param("burst_invuln", 3.3)))
	m.attack_with(action)

func far_skill(action: StringName) -> void:
	m.invuln = maxf(m.invuln, float(param("spin_invuln", 0.8)))
	m.attack_with(action)

func on_call(n: String, _args: Array) -> bool:
	match n:
		"get_round_value":
			pass   # ammo counter art on the body
		"do_hit1":
			_ring()
		"do_hit2":
			var b := m.shoot(BURST, &"hit2")
			b.life = float(param("burst_life", 0.5))
		_:
			return false
	return true

func _ring() -> void:
	_rings = _rings.filter(func(r): return is_instance_valid(r))
	if _rings.size() >= int(param("rings", 6)):
		_recall()
		return
	if m.target == null:
		return
	var to := m.target.global_position - m.global_position
	var r := m.shoot(RING, &"hit1-1")
	r.velocity = to.normalized() * float(param("ring_speed", 240))
	r.distance_left = to.length() + 40.0
	# when its flight ends the ring stays as a trap
	var trap_attack: AttackData = m.data.attacks.get(&"hit1-2", r.attack)
	r.mover = func(p: Projectile, delta: float) -> void:
		if p.distance_left <= 0.0:
			return
		var step := p.velocity * delta
		p.position += step
		p.distance_left -= step.length()
		if p.distance_left <= 0.0:
			p.attack = trap_attack
			p.dealer.reset()
	_rings.append(r)
	_show_rounds()

func _recall() -> void:
	for r in _rings:
		var tw := r.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(r, "global_position", m.global_position, float(param("recall_time", 2.0))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(r.queue_free)
	_rings.clear()
	# the counter refills when the rings are home
	m.after(float(param("recall_time", 2.0)), _show_rounds)

func on_destroy() -> void:
	for r in _rings:
		if is_instance_valid(r):
			r.queue_free()
	var pos: Array = param("next_pos", [1400, 472])
	m.summon(60, Vector2(pos[0], pos[1]))
