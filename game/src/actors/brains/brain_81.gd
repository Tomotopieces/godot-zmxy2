extends "res://src/actors/brains/boss_d.gd"
## Monster81 战神刑天 (7-1, after 刑天): distance bands scaled to the hero. Far: hit2 pull; mid: hit3; close: hit4,
## whose second half is a long forward dash. Kept inside the arena.

func setup() -> void:
	# stats grow with the hero (function Object() { [native code] } averages over players)
	m.max_hp = int(param("hp_base", 500000)) + int(param("hp_per_hero_hp", 50)) * GameState.max_hp()
	m.hp = m.max_hp

func outgoing_damage(a: AttackData) -> int:
	return a.flat + GameState.attack_power() if a else 1

func think(delta: float) -> void:
	super(delta)
	var lim: Array = param("arena_x", [-100, 1050])
	m.global_position.x = clampf(m.global_position.x, lim[0], lim[1])

func moves_while_attacking() -> bool:
	return m.attack_action == &"hit4"

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit2":
			pull_heroes(float(param("pull_time", 0.6)))
		"set_your_father":
			m.invuln = maxf(m.invuln, float(param("dash_invuln", 1.0)))
		_:
			return false
	return true
