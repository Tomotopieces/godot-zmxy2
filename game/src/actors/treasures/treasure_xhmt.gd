extends Treasure
## 血海魔童 (MagicPearl): 魔童连击. Cleanses the hero's debuffs, then jumps next to an enemy and combos it
## (three bursts of three bullets), repeated int(3 + level / 3) times; 木 adds 2 more (the original meant to,
## but its element check never matched).

var _attacks := 0

func begin() -> void:
	hero.cure_debuffs()
	_attacks = 0
	rig.play(&"begin", true)

func _max_attacks() -> int:
	return int(p.attacks_base + level() / int(p.attacks_per_levels)) + (int(p.wood_bonus) if wood() else 0)

func on_call(method: String) -> void:
	match method:
		"set_target":
			_next_target()
		"hit1_1":
			_bullet("fabao_pearl_bullet1", 0)
		"hit1_2":
			_bullet("fabao_pearl_bullet2", 1)
		"hit1_3":
			_bullet("fabao_pearl_bullet3", 2)

func _next_target() -> void:
	var all := candidates()
	if _attacks >= _max_attacks() or all.is_empty():
		finish()
		return
	var m: Monster = all[Rng.randi() % all.size()]
	facing = 1 if global_position.x < m.global_position.x else -1
	rig.play(&"back", true)
	_attacks += 1
	# the immobile 转轮王 (form 3) is aimed at by the head, not the floor it hangs over
	var at := m.center() if m.data.id == 60 else m.global_position
	move_to(at - Vector2(facing * p.side, 0), p.move_time, func(): rig.play(&"hit1", true))

func _bullet(rig_name: String, k: int) -> void:
	var off: Array = p.bullet_offsets[k]
	shoot(rig_name, &"fabao_pearl", global_position + Vector2(off[0], off[1]), facing, power_roll(p.power * level(), "mul"))
