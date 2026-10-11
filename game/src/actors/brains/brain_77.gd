extends "res://src/actors/brains/boss_d.gd"
## Monster77 平等王 (10-6 boss), distance bands. Far: hit2 (wind-up, then one of four variants hit2-1..4) or, when
## no tombstone stands, hit5 raises one (Monster78); mid: hit3; close at low HP: hit4 swaps HP ratios with the hero.

var _variant := 1
var _tomb: Monster

func think(delta: float) -> void:
	if m.state == Monster.State.DEAD or m.is_attacking() or m.target == null:
		super(delta)
		return
	var dx := absf(m.to_target().x)
	if dx <= float(param("near_band", 150)) and float(m.hp) / m.max_hp <= float(param("swap_at", 0.1)) \
			and m.cd("cd3") <= 0.0:
		m.set_cd("cd3", float(param("cd3", 15.0)))
		m.face_target()
		act(&"hit4")
		return
	if dx > float(param("mid_band", 300)) and dx <= float(param("far_band", 800)) and m.cd("cd1") > 0.0 \
			and m.cd("cd4") <= 0.0 and not is_instance_valid(_tomb):
		m.set_cd("cd4", float(param("cd4", 60.0)))
		act(&"hit5")
		return
	super(delta)

func use_skill(action: StringName) -> void:
	if action == &"hit2":
		_variant = Rng.randi_range(1, 4)
	act(action)

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit2":
			m.face_target()
			m.invuln = maxf(m.invuln, float(param("variant_invuln", 0.6)))
			m.attack_with(StringName("hit2-%d" % _variant))
		"do_hit2_1", "do_hit2_2", "do_hit2_3", "do_hit2_4":
			var i := int(n.right(1))
			m.shoot("monster77bullet%d" % i, StringName("hit2-%d" % i), Vector2(100, 0))
		"do_hit5":
			if not is_instance_valid(_tomb):
				_tomb = m.summon(78, Vector2(float(param("tomb_x", 470)), m.global_position.y - 300))
		_:
			return false
	return true

## hit4: the hero drops to 10 % HP and the boss takes the hero's former HP ratio.
func on_hit_hero(hero: Hero, action: StringName) -> void:
	if action != &"hit4":
		return
	var ratio := float(hero.hp) / hero.max_hp
	hero.hp = maxi(1, int(hero.max_hp * float(param("swap_hero_hp", 0.1))))
	m.hp = maxi(1, int(m.max_hp * ratio))

## The tombstone goes with him (the original left it draining after the fight).
func on_destroy() -> void:
	if is_instance_valid(_tomb):
		_tomb.damage_directly(999999)
	super()
