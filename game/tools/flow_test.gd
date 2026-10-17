extends Node
## Walk the screen flow and save screenshots: godot --path game res://tools/flow_test.tscn -- <out dir> [stage e.g. 2,1]
var _out := ""
var _main: Node

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	var st := Vector2i(2, 1)
	if a.size() > 1:
		var p := a[1].split(",")
		st = Vector2i(int(p[0]), int(p[1]))
	# the player's saves are set aside while the test runs with empty slots, and put back at the end
	for i in GameState.SLOTS:
		var f := ProjectSettings.globalize_path(SaveGame.slot_path(i))
		if FileAccess.file_exists(f):
			DirAccess.rename_absolute(f, f + ".bak")
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait(0.5)
	await _shot("1_menu")
	_main._title.new_game.emit()   # (the title lives in main.tscn, not as a swapped screen)
	await _wait(0.3)
	await _shot("1b_select")
	_main._screen.chosen.emit("wukong")
	await _wait(0.4)
	await _shot("2_cartoon")
	for i in 3:
		_click(Vector2(470, 300))
		await _wait(0.2)
	await _wait(0.4)
	await _shot("3_map")
	GameState.souls = 3000
	_main._screen._on_button("showBuySkill")
	await _wait(0.4)
	await _shot("4_skills")
	var shop: SkillShop = _main._screen._popup
	shop._on_button("instrmc/skill1")
	shop._on_button("instrmc/skill3")
	await _wait(0.2)
	await _shot("5_skills_learned")
	shop._on_button("passivebtn")
	await _wait(0.3)
	await _shot("6_passive")
	shop.queue_free()
	GameState.progress = Vector2i(4, 1)
	_main.start_stage(st)
	await _wait(3.0)
	print("paused after stage start: ", get_tree().paused, " hero ", Level.current.hero.global_position)
	await _shot("7_stage")
	var ps: PlayScreen = _main._screen
	ps._on_cleared()
	await _wait(1.6)
	print("children after clear: ", ps.get_children().map(func(c): return c.get_class() + ":" + String(c.name)))
	await _shot("8_win")
	_restore_saves()
	get_tree().quit()

func _restore_saves() -> void:
	for i in GameState.SLOTS:
		var f := ProjectSettings.globalize_path(SaveGame.slot_path(i))
		if FileAccess.file_exists(f + ".bak"):
			DirAccess.remove_absolute(f)
			DirAccess.rename_absolute(f + ".bak", f)

func _click(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		Input.parse_input_event(e)

func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, n])
