extends Treasure
## 罗刹妖伞 (Umbrella): 暴雨梨花. Rises above the hero, then rains 8 poison darts downward in a fan;
## each dart hits once for a little damage and poisons the enemy.

func begin() -> void:
	move_to(Vector2(global_position.x, hero.global_position.y - p.rise), p.rise_time, func(): rig.play(&"hit1", true))

func on_call(method: String) -> void:
	match method:
		"create_stab":
			var n := int(p.stabs)
			for i in n:
				var k := i - n / 2
				var from := global_position + Vector2(k * p.stab_spacing, 0)
				var to := global_position + Vector2(k * p.stab_spread, p.stab_depth)
				_stab(from, (to - from).normalized())
		"hit1_over":
			finish()

## The darts always do the same small damage (the poison is what hurts).
static func _fixed(v: int) -> Callable:
	return func() -> int: return v

func _stab(from: Vector2, dir: Vector2) -> void:
	var pr := shoot("fabao_umbrella_stab", &"fabao_umbrella", from, -1, _fixed(int(p.damage)))
	var poison := int((p.poison_base + p.poison_per_level * level()) * element_mul("mul"))
	var poison_time: float = p.poison
	var poison_tick: float = p.poison_tick
	pr.on_hit = func(t): if t is Monster: t.add_poison(poison, poison_time, poison_tick)
	var turn: float = p.stab_turn
	var v0: float = p.stab_speed
	var jerk: float = p.stab_jerk
	pr.life = turn + p.stab_life
	# fades in while turning to its flight direction, then rushes with growing speed
	pr.modulate.a = 0.0
	var tw := pr.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
	tw.tween_property(pr, "modulate:a", 1.0, turn)
	tw.tween_property(pr, "rotation", atan2(dir.x, -dir.y), turn)
	pr.mover = func(q: Projectile, delta: float) -> void:
		var t := q.age - turn
		if t > 0.0:
			q.position += dir * (v0 + jerk * t * t) * delta
		if absf(q.position.y) > 1000.0:
			q.queue_free()
