extends Node
## Plays a hero's moves in front of monsters and saves a strip of screenshots:
##   godot --path game --position 6000,6000 res://tools/hero_shot.tscn -- <role> <out.png> <keys,comma,separated> [hold_seconds]
## keys: attack skill_u skill_i skill_o skill_l (pressed in order, 1.2 s apart); "+attack" holds attack for hold_seconds.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var role := a[0]
	GameState.new_game(role)
	GameState.level = 30
	GameState.attack = GameState.hero_data.attack_power(30)
	GameState.souls = 99999
	for s in GameState.hero_data.learn_active:
		GameState.skills[StringName(s)] = true
	var ps := PlayScreen.create(Vector2i(1, 1))
	add_child(ps)
	await get_tree().create_timer(0.8, false).timeout
	var lv := ps.level
	var h := lv.hero
	h.refill()
	h.invincible = 999.0
	h.gravity = h.gravity
	var mons: Array[Monster] = []
	for k in 3:
		var m := Monster.create(lv.monster_data(30))
		m.position = h.global_position + Vector2(180 + k * 90, -20)
		lv.add_monster(m)
		mons.append(m)
	await get_tree().create_timer(0.5, false).timeout
	var keys: PackedStringArray = a[2].split(",")
	var hold := float(a[3]) if a.size() > 3 else 1.0
	var frames := 6
	var out := Image.create(frames * 470, 295 * ceili(keys.size() * 1.0), false, Image.FORMAT_RGBA8)
	var row := 0
	for key in keys:
		h.refill()
		h.global_position.x = lv.view_x + 200
		var hold_key := key.begins_with("+")
		var act := key.trim_prefix("+")
		var times := 1
		if act.contains("*"):
			times = int(act.get_slice("*", 1))
			act = act.get_slice("*", 0)
		for t in times:
			Input.action_press(act)
			if hold_key:
				await get_tree().create_timer(hold, false).timeout
			else:
				await get_tree().physics_frame
				await get_tree().physics_frame
			Input.action_release(act)
			if t < times - 1:
				await get_tree().create_timer(0.5, false).timeout
		for f in frames:
			await get_tree().create_timer(0.2, false).timeout
			var img := get_viewport().get_texture().get_image()
			img.resize(470, 295)
			out.blit_rect(img, Rect2i(0, 0, 470, 295), Vector2i(f * 470, row * 295))
		print(key, " action=", h.attack_action, " mp=", h.mp, " mons=", mons.map(func(m): return m.hp if is_instance_valid(m) else -1))
		row += 1
		await get_tree().create_timer(0.8, false).timeout
	out.save_png(a[1])
	get_tree().quit()
