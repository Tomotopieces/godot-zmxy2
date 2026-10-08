class_name Backpack
extends CanvasLayer
## Bag screen (export.pack.BackPack layout): worn gear, 5x5 bag grid, hero stats, item tooltip.
## Three pages (装备 / 道具 / 时装). Click a bag item for 装备 / 出售 (道具: 使用 / 丢弃), click worn gear to take it off.
## Click elsewhere closes the menu. Pauses the game while open.

signal closed

const GRID_ORIGIN := Vector2(484.3, 120.35)
const GRID_COLS := 5
const GRID_ROWS := 5
const CELL := 50.0
const CELL_GAP := 7.0
const ICON_OFFSET := Vector2(0, -2)
const MENU_ROW := Vector2(77, 31)
const MENU_OFFSET := Vector2(25, 25)
const SLOT_PIECES := {&"weapon": "zbwq", &"cloth": "zbfj", &"accessory": "zbsp", &"treasure": "zbfb", &"fashion": "zbsz", &"wing": "zbcb"}
const TABS := {"btn_zb": "equip", "btn_dj": "item", "btn_rw": "look"}   ## page button -> bag page

var _ui: UiLayout
var _grid: Control
var _worn: Control
var _tip: ItemTip
var _menu: UiLayout
var _menu_index := -1
var _tab := "btn_zb"
var _cell_ui: Dictionary

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = Level.VIEW
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_menu())
	add_child(dim)
	_ui = UiLayout.create("backpack")
	add_child(_ui)
	_build_portrait()
	_ui.button_pressed.connect(_on_button)
	_grid = Control.new()
	_grid.position = GRID_ORIGIN
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	_worn = Control.new()
	_worn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_worn)
	_tip = ItemTip.new()
	add_child(_tip)
	GameState.profile_changed.connect(_refresh)
	GameState.equipment_changed.connect(_refresh)
	get_tree().paused = true
	_refresh()

## The portrait plays the original animated clips: the spotlight behind (symbol 137) and Wukong (personmc body)
## wearing the current gear. They replace the layout's frozen first frames.
const GLOW_POS := Vector2(254.55, 209)
var _portrait: Rig

func _build_portrait() -> void:
	_ui.set_visible_piece("personmc", false)
	for c in _ui.get_children():
		for sp: Sprite2D in c.find_children("*", "Sprite2D", true, false):
			if sp.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
				c.visible = false   # the masked spotlight
	var glow := Rig.create("bag_glow")
	glow.position = GLOW_POS
	_ui.add_child(glow)
	_ui.move_child(glow, _ui.get_piece("personmc").get_index())
	glow.play(glow.actions[0])
	_portrait = Rig.create("bag_wukong")
	_portrait.position = (_ui.get_piece("personmc") as Node2D).position
	_ui.add_child(_portrait)
	_ui.move_child(_portrait, _ui.get_piece("personmc").get_index() + 1)
	_portrait.play(_portrait.actions[0])
	_dress_portrait()
	GameState.equipment_changed.connect(_dress_portrait)

func _dress_portrait() -> void:
	var look := GameState.appearance()
	for k in look:
		_portrait.set_equip(k, look[k])

func _exit_tree() -> void:
	get_tree().paused = false

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("open_bag") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()

func _on_button(b: String) -> void:
	if b == "btn_close":
		close()
	elif TABS.has(b):
		_tab = b
		_refresh()

## For tests: switch page without a mouse.
func show_tab(button: String) -> void:
	_on_button(button)

# ------------------------------------------------------------------ content

func _refresh() -> void:
	_close_menu()
	_hide_tip()
	_fill_stats()
	for c in _grid.get_children():
		c.queue_free()
	for c in _worn.get_children():
		c.queue_free()
	# bag cells (only items of the current tab, in bag order)
	var shown := GameState.tab_items(TABS[_tab])
	for k in GRID_COLS * GRID_ROWS:
		var pos := Vector2(k % GRID_COLS, k / GRID_COLS) * (CELL + CELL_GAP)
		var cell := UiLayout.create("pack_cell")
		cell.position = pos
		_grid.add_child(cell)
		if k < shown.size():
			var idx: int = shown[k]
			_grid.add_child(_icon(GameState.bag[idx], pos, _on_bag_click.bind(idx)))
			var n := int(GameState.bag[idx].get("n", 1))
			if n > 1:
				_grid.add_child(_count_label(n, pos))
	# worn gear on the slot frames
	for slot in SLOT_PIECES:
		var item: Dictionary = GameState.worn[slot]
		var piece: Node2D = _ui.get_piece(SLOT_PIECES[slot])
		if item.is_empty() or piece == null:
			continue
		_worn.add_child(_icon(item, piece.position, _on_worn_click.bind(slot)))

## Stack size in the cell corner (PackThings.txtname).
func _count_label(n: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = str(n)
	l.position = pos + Vector2(0, CELL - 20)
	l.size = Vector2(CELL - 4, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _icon(item: Dictionary, pos: Vector2, on_click: Callable) -> TextureRect:
	var d := GameState.item_data(item)
	var t := TextureRect.new()
	t.texture = d.icon
	t.position = pos + ICON_OFFSET
	t.size = Vector2(CELL, CELL)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	t.mouse_entered.connect(_show_tip.bind(item, t))
	t.mouse_exited.connect(_hide_tip)
	t.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(t))
	return t

func _fill_stats() -> void:
	var h: Hero = Level.current.hero if Level.current else null
	var hp := h.hp if h else GameState.max_hp()
	var mp := h.mp if h else GameState.max_mp()
	_ui.set_text("txt_name", "孙悟空")
	_ui.set_text("txt_hp", "%d / %d" % [hp, GameState.max_hp()])
	_ui.set_text("txt_mp", "%d / %d" % [mp, GameState.max_mp()])
	_ui.set_text("txt_exp", "%d / %d" % [GameState.exp, GameState.exp_to_next()])
	_ui.set_text("txt_att", str(GameState.attack_power()))
	_ui.set_text("txt_def", str(GameState.defense()))
	_ui.set_text("txt_baoji", "%d %%" % roundi(GameState.crit() * 100))
	_ui.set_text("txt_sb", "%d %%" % roundi(GameState.miss() * 100))
	_ui.set_text("txt_hx", str(GameState.hp_regen()))
	_ui.set_text("txt_hl", str(GameState.mp_regen()))
	_ui.set_text("txt_lh", str(GameState.souls))
	_ui.set_text("txt_zg", str(GameState.merit))
	_ui.show_frame("levelmc", clampi(GameState.level - 1, 0, 39))
	_ui.show_frame("mc_exp", clampi(roundi(30.0 * GameState.exp / maxf(GameState.exp_to_next(), 1.0)) - 1, 0, 29))

# ------------------------------------------------------------------ actions

## Item menu (threebtn): 装备 / 赠送 / 出售, or for the 道具 page (simplebtn): 使用 / 丢弃.
## A row shows its second frame when unavailable.
func _on_bag_click(icon: Control, index: int) -> void:
	_close_menu()
	_hide_tip()
	_menu_index = index
	var item: Dictionary = GameState.bag[index]
	var d := GameState.item_data(item)
	var enabled := {"bzb": GameState.can_wear(item), "bgy": false, "bmd": d.sellable()}   # 赠送 is 2P only
	if TABS[_tab] == "item":
		enabled = {"buse": GameState.usable(item), "bthrow": true}
	_menu = UiLayout.create("item_menu" if TABS[_tab] == "item" else "pack_menu")
	_menu.position = icon.position + _grid.position + MENU_OFFSET
	add_child(_menu)
	for p in enabled:
		_menu.show_frame(p, 0 if enabled[p] else 1)
		if enabled[p]:
			_menu.add_child(_menu_button(p))

## Hit area over an enabled menu row.
func _menu_button(piece: String) -> Control:
	var art: Node2D = _menu.get_piece(piece)
	var b := Control.new()
	b.position = art.position
	b.size = MENU_ROW
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func(): art.modulate = Color(1.25, 1.25, 1.25))
	b.mouse_exited.connect(func(): art.modulate = Color.WHITE)
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_menu_action(piece))
	return b

func _menu_action(piece: String) -> void:
	var idx := _menu_index
	_close_menu()
	match piece:
		"bzb":
			GameState.wear(idx)
		"bmd":
			var d := GameState.item_data(GameState.bag[idx])
			if GameState.sell(idx):
				_flash_tip("出售 %s，灵魂 +%d" % [d.display_name, d.value])
		"buse":
			_flash_tip(GameState.use_item(idx))
		"bthrow":
			GameState.discard(idx)

func _on_worn_click(_icon: Control, slot: StringName) -> void:
	if not GameState.take_off(slot):
		_flash_tip("背包已满")

func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	_menu_index = -1

# ------------------------------------------------------------------ tooltip

func _show_tip(item: Dictionary, at: Control) -> void:
	_tip.show_for(item, at, CELL)

func _hide_tip() -> void:
	if _tip:
		_tip.visible = false

func _flash_tip(text: String) -> void:
	Toast.show_on(self, text)
