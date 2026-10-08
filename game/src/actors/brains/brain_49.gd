extends "res://src/actors/brains/boss_b.gd"
## Monster49 唐僧怪 (summoned by 孟婆), template B. Far: hit3 sky strike on a hero (warning mark, then a falling
## blast); near: hit2 shockwave, else hit1 or hit4 bolts.

var _mark := Vector2.INF

func attack(_action: StringName = &"hit1") -> void:
	m.face_target()
	m.attack_with(&"hit1" if randf() < 0.5 else &"hit4")

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit1":
			_bolt("monster49bullet1", &"hit1", float(param("bolt1_distance", 600)))
		"do_hit4":
			_bolt("monster49bullet2", &"hit4", float(param("bolt2_distance", 1000)))
		"do_hit2":
			m.shoot("monster49bullet3", &"hit2")
		"do_hit3_1":
			var h: Hero = Level.current.hero
			if h:
				_mark = Vector2(h.global_position.x, m.global_position.y - float(param("mark_up", 300)))
				Fx.spawn("monster49mc1", _mark)
		"do_hit3_2":
			if _mark != Vector2.INF:
				var b := m.shoot("hit4falldown", &"hit3")
				b.global_position = _mark + Vector2(0, float(param("strike_down", 40)))
				_mark = Vector2.INF
		_:
			return false
	return true

func _bolt(rig: String, key: StringName, distance: float) -> void:
	var b := m.shoot(rig, key, Vector2.ZERO, Vector2(float(param("bolt_speed", 240)), 0), distance)
	b.rig.scale.x *= float(param("bolt_scale_x", 0.6))
