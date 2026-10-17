extends Node
## 1-1 camera flow: push -> room locks -> clear -> auto camera -> next room ... godot --headless --path game res://tools/camera_check.tscn
func _ready() -> void:
	Controls.add_gamepad_defaults()
	GameState.new_game("wukong")
	var ps := PlayScreen.create(Vector2i(1, 1)); add_child(ps)
	await get_tree().create_timer(1.0, false).timeout
	var lv := ps.level; var h := lv.hero
	h.invincible = 99999.0
	Engine.time_scale = 1.0
	Input.action_press("move_right")
	var locks := 0
	var autos := 0
	var was_locked := false
	var was_auto := false
	var fails := []
	var kill_at := -1
	var prev_view := lv.view_x
	for i in 6000:
		await get_tree().physics_frame
		if lv.locked and not was_locked:
			locks += 1
			var sx: float = lv.stops[lv.stop_index].x
			print(i, " LOCK view ", snappedf(lv.view_x, 0.1), " stop right edge gap ", snappedf(sx - (lv.view_x + 940.0), 0.1))
			if absf(sx - (lv.view_x + 940.0)) > 3.0: fails.append("lock gap")
			kill_at = i + 100
		if lv.auto_scroll and not was_auto:
			autos += 1
			print(i, " AUTO starts view ", snappedf(lv.view_x, 0.1))
		if was_auto and not lv.auto_scroll:
			print(i, " AUTO ends view ", snappedf(lv.view_x, 0.1), " hero screen x ", snappedf(h.global_position.x - lv.view_x, 0.1))
		was_locked = lv.locked
		was_auto = lv.auto_scroll
		if lv.locked and kill_at == i:
			for m in lv.monsters(): m.queue_free()
			for sp in lv.stops[lv.stop_index].spawners: sp.total = 0
		# locked: the screen never shows anything right of the stop; the view never jumps
		if lv.locked and lv.view_x + 940.0 > lv.stops[lv.stop_index].x + 2.0: fails.append("past stop")
		if absf(lv.view_x - prev_view) > 13.0:
			fails.append("view jump %d" % i)
			print("jump ", i, " ", snappedf(prev_view, 0.1), " -> ", snappedf(lv.view_x, 0.1), " hero screen ", snappedf(h.global_position.x - prev_view, 1))
		prev_view = lv.view_x
		if lv.stop_index >= lv.stops.size() and i > 100 and lv.view_x > lv.stops[-1].x - 880.0:
			break
	print("locks ", locks, " autos ", autos, " final view ", snappedf(lv.view_x, 1), " hero x ", snappedf(h.global_position.x, 1))
	# back: with the hero walking left the camera follows back, but not past the room's limit
	Input.action_release("move_right")
	Input.action_press("move_left")
	for i in 600: await get_tree().physics_frame
	print("after walking back: view ", snappedf(lv.view_x, 1), " hero x ", snappedf(h.global_position.x, 1))
	if locks < 5: fails.append("flow incomplete")
	if autos > 0: fails.append("forced scroll after a room")
	print("CAMERA CHECK ", "FAILED " + str(fails) if not fails.is_empty() else "OK")
	get_tree().quit(1 if not fails.is_empty() else 0)
