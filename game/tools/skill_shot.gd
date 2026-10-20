extends Node
## Fire a skill in 1-1 and save frames, then a montage:
##   godot --path game res://tools/skill_shot.tscn -- --out=<dir> --keys=skill_u [--at=0.05,0.1,0.15] [--face=left] [--rage] [--fx=<puppet>]
var _out := ""
var _keys := PackedStringArray()
var _at := PackedFloat32Array([0.05, 0.1, 0.15, 0.2, 0.3, 0.4])
var _face := 1
var _rage := false
var _fx := ""
var _spawn := 0
var _stage := Vector2i(1, 1)
var _shots: Array[Image] = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--keys="): _keys = a.substr(7).split(",")
		elif a.begins_with("--at="): _at = PackedFloat32Array(Array(a.substr(5).split(",")).map(func(x): return x.to_float()))
		elif a == "--face=left": _face = -1
		elif a == "--rage": _rage = true
		elif a.begins_with("--fx="): _fx = a.substr(5)
		elif a.begins_with("--spawn="): _spawn = int(a.substr(8))   # monster next to the hero; frames timed from its spawn
		elif a.begins_with("--stage="):
			var q := a.substr(8).split(",")
			_stage = Vector2i(int(q[0]), int(q[1]))   # spawn an effect puppet at the hero instead of pressing keys
	GameState.new_game()
	for s in GameState.hero_data.learn_active:
		GameState.skills[StringName(s)] = true
	add_child(PlayScreen.create(_stage))
	await get_tree().create_timer(2.2).timeout
	var h := Level.current.hero
	h.global_position.x = 470 if _face > 0 else 600
	h.facing = _face
	if _rage:
		h.rage = h.data.rage_max
	await get_tree().create_timer(0.3).timeout
	if _fx != "":
		Fx.spawn(_fx, h.center())
	if _spawn > 0:
		h.invincible = 999.0
		var mon := Monster.create(Level.current.monster_data(_spawn))
		mon.position = h.global_position + Vector2(260 * _face, -40)
		Level.current.add_monster(mon)
	for k in _keys:
		Input.action_press(k)
	var t0 := Time.get_ticks_msec()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for k in _keys:
		Input.action_release(k)
	for t in _at:
		while (Time.get_ticks_msec() - t0) / 1000.0 < t:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_shots.append(get_viewport().get_texture().get_image())
	var w := 470
	var hgt := 295
	var cols := 3
	var rows := ceili(_shots.size() / float(cols))
	var m := Image.create(w * cols, hgt * rows, false, Image.FORMAT_RGBA8)
	for i in _shots.size():
		var im := _shots[i]
		im.convert(Image.FORMAT_RGBA8)
		im.resize(w, hgt, Image.INTERPOLATE_BILINEAR)
		m.blit_rect(im, Rect2i(0, 0, w, hgt), Vector2i((i % cols) * w, (i / cols) * hgt))
	m.save_png(_out + "/" + ("m%d" % _spawn if _spawn > 0 else (_fx if _fx != "" else "_".join(_keys))) + ".png")
	get_tree().quit()
