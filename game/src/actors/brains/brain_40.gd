extends "res://src/actors/brains/boss_b.gd"
## Monster40 阎罗王 (2-3 boss), template B. Far skill (hit3) opens a summoning door under the hero at 80 / 60 / 40 % HP:
## after a delay the door releases totem 53, 54, then 55. After the third door the far skill is a plain swing.
## Near: hit2 wave (cooldown), else hit1. When it dies every totem it summoned dies too.

const DOOR := "doorcalled"
const TOTEMS := [53, 54, 55]
const THRESHOLDS := [0.8, 0.6, 0.4]

var _doors := 0
var _totems: Array[Monster] = []

func setup() -> void:
	m.set_cd("far", float(param("far_cd", 3.0)))

func far_skill(_action: StringName) -> void:
	if _doors < 3 and float(m.hp) / m.max_hp <= THRESHOLDS[_doors]:
		m.invuln = maxf(m.invuln, float(param("summon_invuln", 1.17)))
		m.attack_with(&"hit3")
	elif _doors >= 3:
		attack()
	else:
		follow()

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit3":
			_open_door()
		"do_hit2":
			m.shoot("monster40bullet1", &"hit2", Vector2(40, 0))
		_:
			return false
	return true

func _open_door() -> void:
	var hero: Hero = m.world.hero
	if hero == null or _doors >= 3:
		return
	var pos := Vector2(hero.global_position.x, m.global_position.y + 80)
	Fx.spawn(DOOR, pos)
	var id: int = TOTEMS[_doors]
	_doors += 1
	m.after(float(param("summon_delay", 2.0)), func():
		if m.state != Monster.State.DEAD:
			var t := m.summon(id, pos + Vector2(0, -190))
			if t:
				_totems.append(t))

func on_died() -> void:
	for t in _totems:
		if is_instance_valid(t):
			t.damage_directly(99999)
