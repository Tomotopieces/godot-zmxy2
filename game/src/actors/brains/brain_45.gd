extends "res://src/actors/brains/boss_b.gd"
## Monster45 白骨精 (5-1 boss), three forms. Template B: far -> hit3 gaze (heroes on her facing side who look at
## her are petrified), near -> hit2 growing blast, else hit1. Forms 1 and 2 revive on death: a long invulnerable
## "reburn" (souls drop each time, the exit portal is open so the player may leave), then the next form with more
## HP, defence and attack power (Monster45.setInfo). The third death is final. Her wings show the current form.

var _form := 1
var _reviving := false

func setup() -> void:
	_apply_form()

## Numbers of the current form on a private copy of the monster data (attacks, defence, drops).
func _apply_form() -> void:
	var f: Dictionary = param("forms", [])[_form - 1]
	var d: MonsterData = m.data.duplicate()
	d.attacks = {}
	for k in m.data.attacks:
		var a: AttackData = m.data.attacks[k].duplicate()
		a.flat = int(f.power)
		d.attacks[k] = a
	var kb: Array = f.hit2_knockback
	d.attacks[&"hit2"].knockback = Vector2(kb[0], kb[1])
	d.def = int(f.def)
	d.mdef = float(f.mdef)
	d.equip_chance = float(f.equip_chance)
	d.equip_drops = PackedStringArray(f.drops)
	d.stone_rate = float(f.stone_rate)
	m.data = d
	m.max_hp = int(f.hp)
	m.hp = m.max_hp
	m.rig.set_equip("form", _form)

func can_be_hit() -> bool:
	return not _reviving

func intercept_death() -> bool:
	if _form >= 3:
		return false
	_reviving = true
	m.end_attack()
	m.velocity = Vector2.ZERO
	m.play_action(&"dead")   # its last frame calls check_re_burn
	return true

func on_call(n: String, _args: Array) -> bool:
	match n:
		"check_re_burn":
			if not _reviving:
				return true   # final death: the normal boss death takes over
			_form += 1
			Loot.drop(m)
			Level.current.open_door()
			m.play_action(&"reburn")
		"set_info":
			_apply_form()
			_reviving = false
			Level.current.close_door()
			m.state = Monster.State.MOVE
		"do_hit2":
			var b := m.shoot("monster45bullet1", &"hit2", Vector2(0, 80))
			b.rig.scale *= 1.0 + float(param("blast_growth", 0.4)) * (_form - 1)
		"do_hit3":
			_gaze()
		_:
			return false
	return true

## Heroes in front of her and facing her are petrified (eyefix): no input for a while.
func _gaze() -> void:
	var t := float(param("gaze_time", 5.0)) + float(param("gaze_per_form", 0.08)) * (_form - 1)
	for h: Hero in Level.current.heroes():
		if not h.can_be_hit():
			continue
		var in_front := signf(h.global_position.x - m.global_position.x) == float(m.facing)
		var looking := h.facing == -m.facing
		if in_front and looking:
			h.add_debuff(&"eyefix", t)
