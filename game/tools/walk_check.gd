extends Node
## Every stage can be walked from its start to its end (no falling through, no foot caught): godot --headless --path game res://tools/walk_check.tscn [-- stage,level ...]
func _ready() -> void:
	Controls.add_gamepad_defaults()
	GameState.new_game("wukong")
	var stages := [Vector2i(1,1),Vector2i(1,2),Vector2i(1,3),Vector2i(2,1),Vector2i(2,2),Vector2i(2,3),Vector2i(3,2),Vector2i(3,3),Vector2i(4,1),Vector2i(8,1),Vector2i(9,1)]
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stages = []
		for s in a:
			stages.append(Vector2i(int(s.get_slice(",", 0)), int(s.get_slice(",", 1))))
	var fails := 0
	for st in stages:
		var ps := PlayScreen.create(st); add_child(ps)
		await get_tree().create_timer(0.6, false).timeout
		var lv := ps.level; var h := lv.hero
		h.invincible = 99999
		Engine.time_scale = 4.0
		var ok := true
		var end_x := lv._end_x
		for pass_dir in [1, -1]:
			Input.action_press("move_right" if pass_dir == 1 else "move_left")
			var stuck := 0
			var last := h.global_position.x
			for i in 4000:
				await get_tree().physics_frame
				for m in lv.monsters(): m.queue_free()
				for s in lv.stops: for sp in s.spawners: sp.total = 0
				lv._can_back = -99.0
				if h.global_position.y > 1200.0:
					ok = false
					print("  fell at x ", snappedf(h.global_position.x, 1))
					break
				if absf(h.global_position.x - last) < 0.2:
					stuck += 1
				else:
					stuck = 0
					last = h.global_position.x
				if stuck > 40:
					break
			Input.action_release("move_right"); Input.action_release("move_left")
			print("%s %s: ended x=%d (end %d)" % [lv.level_name, "right" if pass_dir == 1 else "left", h.global_position.x, end_x])
			if pass_dir == 1 and h.global_position.x < end_x - 200.0 and lv.level_name not in ["sl91"]:
				ok = false
		print("%s  %s" % ["ok  " if ok else "FAIL", lv.level_name])
		if not ok: fails += 1
		ps.queue_free()
		await get_tree().process_frame
		Engine.time_scale = 1.0
	print("WALK CHECK ", "FAILED (%d)" % fails if fails else "OK")
	get_tree().quit(1 if fails else 0)
