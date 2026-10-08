extends "res://src/actors/brains/boss_b.gd"
## Monster64 宋帝王 (9-1 boss), template B. hit1 / hit3 are effects at himself; hit2 marks the target's spot and
## erupts there. On death a loot object (65 or 66) appears after a short delay.

var _mark := Vector2.INF

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit1":
			m.shoot("monster64bullet3", &"hit1")
		"do_hit3":
			m.shoot("monster64bullet2", &"hit3")
		"do_hit2_pre":
			if m.target:
				_mark = Vector2(m.target.global_position.x, float(param("floor_y", 480)))
		"do_hit2":
			if _mark != Vector2.INF:
				m.shoot("monster64bullet1", &"hit2").global_position = _mark
				_mark = Vector2.INF
		_:
			return false
	return true

func on_destroy() -> void:
	super()
	var lv := m.world
	var pos: Array = param("loot_pos", [1450, 310])
	m.get_tree().create_timer(float(param("loot_delay", 2.0)), false).timeout.connect(func():
		if is_instance_valid(lv):
			var md := lv.monster_data(65 + (Rng.randi() % 2))
			if md:
				var o := Monster.create(md)
				o.position = Vector2(pos[0], pos[1])
				lv.add_monster(o))
