extends "res://src/actors/brains/boss_b.gd"
## Monster67 五官王 (10-2 boss), template B. Far: hit3 summons a ghost turret (Monster68) while the screen has
## room; near: hit2 (three pillars, then a poison wave in front), else hit1.

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit3":
			if m.world.monsters().size() < int(param("max_monsters", 4)):
				m.summon(68, m.global_position + Vector2(float(param("turret_dx", 70)) * m.facing, -30))
		"do_hit2_pre":
			for dx in param("pillars_x", [138, 100, 72]):
				m.shoot("monster67bullet2", &"hit2-1", Vector2(dx, -80))
		"do_hit2":
			m.shoot("monster67bullet1", &"hit2", Vector2(160, 60))
		_:
			return false
	return true
