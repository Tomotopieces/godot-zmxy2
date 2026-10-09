extends MonsterBrain
## 泰山王 (10-4 boss), four forms that hand over to each other keeping their HP:
##   73 normal --(timer)--> 74 reflect --(timer)--> 73;   73 below 50 % HP --> 75 big
##   75 big --(timer)--> 76 big reflect --(timer)--> 75
## Reflect forms return all damage to the attacker. AI: far -> hit2 dash (cooldown) else every check tick 50 %
## attack / chase; near -> every check tick 50 % hit1. Params: big_at (HP ratio), next_form, to_big,
## swap_after (s, timer to the next form), reflect.

var _check := 0.0
var _swap := 0.0
var _handing_over := false

func setup() -> void:
	_swap = float(param("swap_after", 20.0))

func think(delta: float) -> void:
	if _handing_over or m.state != Monster.State.MOVE:
		return
	if param("to_big", 0) and float(m.hp) / m.max_hp < float(param("big_at", 0.5)):
		_become(int(param("to_big", 75)))
		return
	_swap -= delta
	if _swap <= 0.0 and int(param("next_form", 0)) > 0:
		_become(int(param("next_form", 0)))
		return
	if m.target == null:
		wander(delta)
		select_target()
		return
	var d := m.to_target()
	if absf(d.y) > float(param("reach_y", 600)):
		wander(delta)
		return
	_check -= delta
	if absf(d.x) > m.data.attack_range:
		if m.cd("dash") <= 0.0:
			m.set_cd("dash", float(param("dash_cd", 7.5)))
			m.face_target()
			act(&"hit2")
		elif _check <= 0.0:
			_check = float(param("check", 1.0))
			if Rng.randi() % 100 < m.data.attack_chance:
				attack()
			else:
				follow()
	elif _check <= 0.0:
		_check = float(param("check", 1.0))
		m.dir = 0
		if Rng.randi() % 100 < m.data.attack_chance:
			attack()

## Replace this form by another one with the same HP; the old one fades out.
func _become(id: int) -> void:
	_handing_over = true
	var nx := m.summon(id, m.global_position + Vector2(0, -10))
	if nx:
		nx.hp = mini(m.hp, nx.max_hp)
	m.invuln = 9999.0
	m.vanish()

func moves_while_attacking() -> bool:
	return m.attack_action == &"hit2"

func modify_damage(h: Hit, dmg: int) -> int:
	if param("reflect", false) and h.source is Hero:
		(h.source as Hero).lose_hp(dmg)
	return dmg

## Form changes are not deaths: only a real kill opens the exit.
func on_destroy() -> void:
	if not _handing_over:
		super()
