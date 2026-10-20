extends "res://src/actors/brains/boss_d.gd"
## Monster48 悟空怪 (summoned by 孟婆): distance bands (template D) with Wukong's moves.
## Far: hit2 dash; mid: hit3; close: hit4 ground blast (a single-frame action that lasts while its effect plays).
## Basic attacks pick one of hit1 / hit5 / hit6 / hit7.

const BLAST := "monster48bullet1"
const MELEE := [&"hit1", &"hit5", &"hit6", &"hit7"]

## hit4 (the fire blast): the body clip shows its pose for one frame and then nothing for the rest of the move; the
## blast is the only thing on screen.
func think(delta: float) -> void:
	m.puppet.visible = not (m.attack_action == &"hit4" and m.is_attacking())
	super(delta)

func on_died() -> void:
	m.puppet.visible = true

func attack(_action: StringName = &"hit1") -> void:
	m.face_target()
	m.attack_with(MELEE[Rng.randi() % MELEE.size()])

func use_skill(action: StringName) -> void:
	act(action)   # (its invulnerable window ends when the move does: invuln_until_stand)
	if action == &"hit2":
		m.velocity.x = m.facing * float(param("dash_speed", 720))

func moves_while_attacking() -> bool:
	return m.attack_action == &"hit2"

func on_call(n: String, _args: Array) -> bool:
	if n != "do_hit4":
		return false
	var b := m.shoot(BLAST, &"hit4")
	b.tree_exiting.connect(m.owned(func():
		if m.attack_action == &"hit4":
			m.finish_action(&"hit4")), CONNECT_DEFERRED)
	return true
