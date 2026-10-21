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
func _trigger(axis: int) -> void:
	for v in [1.0, 0.0]:
		var e := InputEventJoypadMotion.new()
		e.axis = axis
		e.axis_value = v
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
func _nav() -> PadFocus:
	return _main.get_children().filter(func(c): return c is PadFocus)[0]
func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()
func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	var nav := _nav()
	_check("main menu has pad targets", nav._scope() != null)
	await _btn(JOY_BUTTON_DPAD_DOWN)
	_check("first press shows the highlight", _focus() != null and nav._shown)
	var first: Control = _focus()
	await _btn(JOY_BUTTON_DPAD_DOWN)
	_check("D-pad moves it down", _focus() != first and _focus().get_global_rect().get_center().y > first.get_global_rect().get_center().y)
	# A on "继续游戏" opens the load panel, which is a popup layer on top
	var seen := {}
	for i in 6:
		seen[_focus()] = true
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
	var f: Control = _focus()
	_check("select role: focus on a portrait", f != null)
	await _btn(JOY_BUTTON_DPAD_RIGHT)
	_check("select role: moves to the next portrait", _focus() != f)
	_main.show_map()
	await get_tree().create_timer(0.5).timeout
	await _btn(JOY_BUTTON_DPAD_LEFT)
	_check("stage map reachable", _focus() != null)
	# a stage: the HUD alone does not capture the pad
	GameState.new_game("wukong")
	_main.start_stage(Vector2i(1, 1))
	await get_tree().create_timer(1.0).timeout
	_check("in a stage the pad is the game's", nav._scope() == null)
	var ps: PlayScreen = _main._screen
	ps.open_menu(&"bag")
	await get_tree().create_timer(0.4).timeout
	_check("backpack takes the pad", nav._scope() != null)
	await _btn(JOY_BUTTON_DPAD_DOWN)
	_check("backpack highlight", _focus() != null and ps._menu.page.is_ancestor_of(_focus()))
	# LT / RT switch tabs (法宝 is skipped without a worn treasure)
	await _trigger(JOY_AXIS_TRIGGER_RIGHT)
	_check("RT: 技能 tab", ps._menu.tab == &"skill")
	await _trigger(JOY_AXIS_TRIGGER_RIGHT)
	_check("RT skips 法宝 without a treasure: 设置", ps._menu.tab == &"settings")
	await _trigger(JOY_AXIS_TRIGGER_RIGHT)
	_check("RT wraps to 背包", ps._menu.tab == &"bag")
	await _trigger(JOY_AXIS_TRIGGER_LEFT)
	_check("LT: 设置", ps._menu.tab == &"settings")
	await _btn(JOY_BUTTON_DPAD_DOWN)
	_check("settings page takes the pad", _focus() != null and ps._menu.page.is_ancestor_of(_focus()))
	# an item menu: B closes the menu only; selling keeps the highlight on that cell when the next item moves in
	ps._menu.close()
	await get_tree().create_timer(0.3).timeout
	for id in ["ptxzf", "ptxzf", "ptxzf"]:
		var e := EquipmentCatalog.find(id)
		if e:
			GameState.add_to_bag(e.roll())
	var shown_before := GameState.tab_items("equip").size()
	ps.open_menu(&"bag")
	await get_tree().create_timer(0.4).timeout
	var bag: Backpack = ps._menu.page
	var cells: Array = bag._grid.get_children().filter(func(c): return c is TextureRect)
	await _btn(JOY_BUTTON_DPAD_DOWN)
	cells[0].grab_focus()
	var cell_center: Vector2 = cells[0].get_global_rect().get_center()
	await _btn(JOY_BUTTON_A)
	await get_tree().create_timer(0.2).timeout
	_check("A on an item opens its menu", bag._menu != null)
	_check("pad: LB / RB hints shown", bag._ui.piece("LbIcon").visible and ps._menu._ui.piece("LtIcon").visible)
	await _btn(JOY_BUTTON_B)
	await get_tree().create_timer(0.2).timeout
	_check("B closes the item menu, not the backpack", is_instance_valid(bag) and ps._menu != null and bag._menu == null)
	await _btn(JOY_BUTTON_A)
	await get_tree().create_timer(0.2).timeout
	bag._menu_action("Sell")
	await get_tree().create_timer(0.3).timeout
	_check("after selling the highlight stays on that cell (%d items before)" % shown_before,
		_focus() != null and _focus().get_global_rect().get_center().distance_to(cell_center) < 2.0)
	await _btn(JOY_BUTTON_B)
	await get_tree().create_timer(0.3).timeout
	_check("B closes the menu", ps._menu == null)
	# LB / RB switch the backpack's pages
	ps.open_menu(&"bag")
	await get_tree().create_timer(0.4).timeout
	bag = ps._menu.page
	await _btn(JOY_BUTTON_RIGHT_SHOULDER)
	_check("RB: 道具 page", bag._tab == "BtnDaoJu")
	await _btn(JOY_BUTTON_LEFT_SHOULDER)
	await _btn(JOY_BUTTON_LEFT_SHOULDER)
	_check("LB twice: 时装 page", bag._tab == "BtnShiZhuang")
	# a learned skill keeps its coloured picture under the pad's focus
	ps._menu.show_tab(&"skill")
	await get_tree().create_timer(0.3).timeout
	var shop: SkillShop = ps._menu.page
	var icon: Button = shop._active[0]
	icon.disabled = true
	icon.grab_focus()
	_check("learned skill icon: focus does not show the grey picture", icon.get_theme_stylebox(&"focus") is StyleBoxEmpty)
	ps._menu.close()
	await get_tree().create_timer(0.3).timeout
	print("PAD CHECK ", "FAILED (%d)" % _fails if _fails else "OK")
	get_tree().quit(1 if _fails else 0)
