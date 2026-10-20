extends Treasure
## 五毒兽 (WuDu). Every few seconds (while there are enemies and the hero has the MP, which it does not spend)
## it spits an accelerating bullet at a random enemy. H: rushes next to a random enemy and casts its spell
## (雷 / 火, rolled when it was made); after 五毒丹 it casts the full-screen version instead, even with no enemy.

var _auto_t := 0.0

func setup() -> void:
	_auto_t = p.first_auto

func _spell() -> Dictionary:
	return p.spells[item.spell]

func _strong() -> bool:
	return item.strong

func step(delta: float) -> void:
	_auto_t = maxf(_auto_t - delta, 0.0)
	if _auto_t <= 0.0 and not using and not candidates().is_empty() and hero.mp >= Forge.skill_cost(item):
		if _move:
			_move.kill()
		using = true
		puppet.play(&"hit1", true)
		_auto_t = p.auto

func can_use() -> bool:
	return _strong() or not candidates().is_empty()

func begin() -> void:
	if _strong():
		puppet.play(&"hit2-2", true)
		return
	var all := candidates()
	var m: Monster = all[Rng.randi() % all.size()]
	var c := m.center()
	var tx: float = c.x - p.side if global_position.x < c.x else c.x + p.side
	facing = 1 if global_position.x < tx else -1
	move_to(Vector2(tx, c.y), p.move_time, func(): puppet.play(&"hit2-1", true))

func on_call(method: String) -> void:
	match method:
		"hit1_do":
			_spit()
		"do_hit2_1":
			var s := _spell()
			var off: Array = s.small_offset
			shoot(s.small, StringName(s.small_attack), global_position + Vector2(off[0] * facing, off[1]), facing, power_roll(float(s.small_power) * level()))
		"do_hit2_2":
			var s := _spell()
			var sc: Array = s.big_screen
			var v := world.view_rect()
			shoot(s.big, StringName(s.big_attack), Vector2(v.position.x + sc[0], sc[1]), -1, power_roll(float(s.big_power) * level()))
		"hit1_over":
			finish()

func _spit() -> void:
	var all := candidates()
	if all.is_empty():
		return
	var m: Monster = all[Rng.randi() % all.size()]
	var dir := (m.center() - global_position).normalized()
	facing = 1 if dir.x >= 0.0 else -1
	var pr := shoot("fabao_wudu_bullet1", &"fabao_wudu_hit1", global_position, facing, func() -> int: return GameState.attack_power())
	pr.velocity = dir * p.bullet_speed
	pr.accel = dir * p.bullet_accel
	pr.distance_left = p.bullet_distance
