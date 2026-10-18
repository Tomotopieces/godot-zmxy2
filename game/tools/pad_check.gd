extends Node
## Gamepad navigation: drives menus with synthetic pad events. godot --headless --path game res://tools/pad_check.tscn
var _fails := 0
var _main: Node
func _check(what: String, ok: bool) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
func _btn(b: int) -> void:
	for p in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.pressed = p
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame
func _nav() -> PadNav:
	return _main.get_children().filter(func(c): return c is PadNav)[0]
func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	var nav := _nav()
	_check("main menu has pad targets", nav.active())
	await _btn(JOY_BUTTON_DPAD_DOWN)
	_check("first press shows the highlight", nav._focus != null)
	var first: Control = nav._focus
	await _btn(JOY_BUTTON_DPAD_DOWN)
	_check("D-pad moves it down", nav._focus != first and nav._focus.get_global_rect().get_center().y > first.get_global_rect().get_center().y)
	# A on "继续游戏" opens the load panel, which is a popup layer on top
	var seen := {}
	for i in 6:
		seen[nav._focus] = true
		await _btn(JOY_BUTTON_DPAD_UP)
	await _btn(JOY_BUTTON_DPAD_DOWN)
	await _btn(JOY_BUTTON_A)
	await get_tree().create_timer(0.3).timeout
	_check("A activates a button (a screen opened)", _main.get_children().any(func(c): return c is SelectRole or (c is MainMenu and c._popup != null)))
	# new game -> select role: three portraits reachable
	get_tree().paused = false
	_main.show_select_role()
	await get_tree().create_timer(0.4).timeout
	await _btn(JOY_BUTTON_DPAD_LEFT)
	await _btn(JOY_BUTTON_DPAD_LEFT)
	await _btn(JOY_BUTTON_DPAD_LEFT)
	var f: Control = nav._focus
	_check("select role: focus on a portrait", f != null)
	await _btn(JOY_BUTTON_DPAD_RIGHT)
	_check("select role: moves to the next portrait", nav._focus != f)
	_main.show_map()
	await get_tree().create_timer(0.5).timeout
	await _btn(JOY_BUTTON_DPAD_LEFT)
	_check("stage map reachable", nav._focus != null)
	# a stage: the HUD alone does not capture the pad
	GameState.new_game("wukong")
	_main.start_stage(Vector2i(1, 1))
	await get_tree().create_timer(1.0).timeout
	_check("in a stage the pad is the game's", not nav.active())
	var ps: PlayScreen = _main._screen
	ps._open_bag()
	await get_tree().create_timer(0.4).timeout
	_check("backpack takes the pad", nav.active())
	await _btn(JOY_BUTTON_DPAD_DOWN)
	_check("backpack highlight", nav._focus != null)
	# an item menu: B closes the menu only; selling keeps the highlight on that cell when the next item moves in
	ps._bag.close()
	await get_tree().create_timer(0.3).timeout
	for id in ["ptxzf", "ptxzf", "ptxzf"]:
		var e := EquipmentCatalog.find(id)
		if e:
			GameState.add_to_bag(e.roll())
	var shown_before := GameState.tab_items("equip").size()
	ps._open_bag()
	await get_tree().create_timer(0.4).timeout
	var cells: Array = ps._bag._grid.get_children().filter(func(c): return c is TextureRect)
	await _btn(JOY_BUTTON_DPAD_DOWN)
	nav._gain(cells[0])
	var cell_center: Vector2 = cells[0].get_global_rect().get_center()
	await _btn(JOY_BUTTON_A)
	await get_tree().create_timer(0.2).timeout
	_check("A on an item opens its menu", ps._bag._menu != null)
	await _btn(JOY_BUTTON_B)
	await get_tree().create_timer(0.2).timeout
	_check("B closes the item menu, not the backpack", ps._bag != null and is_instance_valid(ps._bag) and ps._bag._menu == null)
	await _btn(JOY_BUTTON_A)
	await get_tree().create_timer(0.2).timeout
	ps._bag._menu_action("bmd")
	await get_tree().create_timer(0.3).timeout
	_check("after selling the highlight stays on that cell (%d items before)" % shown_before,
		nav._focus != null and is_instance_valid(nav._focus) and nav._focus.get_global_rect().get_center().distance_to(cell_center) < 2.0)
	await _btn(JOY_BUTTON_B)
	await get_tree().create_timer(0.3).timeout
	_check("B closes the backpack", ps._bag == null or not is_instance_valid(ps._bag))
	print("PAD CHECK ", "FAILED (%d)" % _fails if _fails else "OK")
	get_tree().quit(1 if _fails else 0)
