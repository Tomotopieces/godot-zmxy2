class_name Backpack
extends CanvasLayer
## Bag screen (export.pack.BackPack layout): worn gear, 5x5 bag grid, hero stats, item tooltip.
## Three pages (装备 / 道具 / 时装). Click a bag item for 装备 / 出售 (道具: 使用 / 丢弃), click worn gear to take it off.
## Click elsewhere closes the menu. Pauses the game while open.

signal closed

const GRID_COLS := 5
const GRID_ROWS := 5
const CELL := 50.0
const CELL_GAP := 7.0
const SLOT_SCENE := "res://scenes/ui/backpack/slot.tscn"   ## the 25 bag cells are scene instances of it
const MENU_OFFSET := Vector2(25, 25)
const MOON_MENU_HEIGHT := 142.0   ## the exchange menu is taller than the plain one: keep it on screen
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
	dim.size = Layers.VIEW
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close_menu())
	add_child(dim)
	_ui = UiLayout.create("backpack")
	add_child(_ui)
	_build_portrait()
	_ui.button_pressed.connect(_on_button)
	_grid = _ui.get_node("Grid")   # the scene's own 5x5 cells: nothing is created here

	_worn = Control.new()
	_worn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_worn)
	_tip = ItemTip.new()
	add_child(_tip)
	GameState.profile_changed.connect(_refresh)
	GameState.equipment_changed.connect(_refresh)
	get_tree().paused = true
	_refresh()
	UiFade.fade_in(self)

## The portrait plays the original animated clips: the spotlight behind (the scene's SpotLight) and the hero
## (personmc body) wearing the current gear, which replaces the layout's frozen first frame.
var _portrait: Rig

func _build_portrait() -> void:
	var glow := _ui.get_piece("spotlight") as Rig
	glow.play(glow.actions[0])
	_ui.set_visible_piece("personmc", false)
	_portrait = Rig.create("bag_" + GameState.hero_data.role)
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
	UiFade.close(self)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and _menu:   # Esc / the pad's B: an open item menu closes first
		get_viewport().set_input_as_handled()
		_close_menu()
	elif e.is_action_pressed("open_bag") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()

func _on_button(b: String) -> void:
	if b == "btn_close":
		close()
	elif TABS.has(b):
		Snd.ui()
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
		if not _is_cell(c):      # the cells stay: only the icons and count labels of the last refresh go
			c.queue_free()
	for c in _worn.get_children():
		c.queue_free()
	# the items of the current tab, one per scene cell, in bag order (the cells' own positions are their grid slots)
	var shown := GameState.tab_items(TABS[_tab])
	var k := 0
	for cell in _grid.get_children():
		if not _is_cell(cell):
			continue
		var pos: Vector2 = (cell as Control).position
		if k < shown.size():
			var idx: int = shown[k]
			_grid.add_child(_icon(GameState.bag[idx], pos, _on_bag_click.bind(idx)))
			var n := GameState.bag[idx].n
			if n > 1:
				_grid.add_child(_count_label(n, pos))
		k += 1
	# worn gear on the slot frames (an empty slot keeps its caption, an occupied one hides it)
	for slot in SLOT_PIECES:
		var item: Item = GameState.worn[slot]
		var piece: Node2D = _ui.get_piece(SLOT_PIECES[slot])
		if piece == null:
			continue
		var caption := piece.find_child("Caption", true, false) as Label
		if caption:
			caption.visible = item == null
		if item == null:
			continue
		_worn.add_child(_icon(item, piece.position, _on_worn_click.bind(slot)))

## A bag cell is one of the Slot instances put in the scene's Grid by hand.
func _is_cell(c: Node) -> bool:
	return c.scene_file_path == SLOT_SCENE

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

## The item's drop picture (掉落物), fitted into the 50x50 cell; without one the old framed icon is centred as before.
func _icon(item: Item, pos: Vector2, on_click: Callable) -> TextureRect:
	var t := ItemIcon.create(item, CELL).place(pos)
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	t.mouse_entered.connect(_show_tip.bind(item, t))
	t.mouse_exited.connect(_hide_tip)
	t.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(t))
	PadNav.mark(t)
	return t

func _fill_stats() -> void:
	var h: Hero = Level.current.hero if Level.current else null
	var hp := h.hp if h else GameState.max_hp()
	var mp := h.mp if h else GameState.max_mp()
	_ui.set_text("txt_name", GameState.hero_data.title)
	_ui.set_text("txt_hp", "%d / %d" % [hp, GameState.max_hp()])
	_ui.set_text("txt_mp", "%d / %d" % [mp, GameState.max_mp()])
	_ui.set_text("txt_exp", "%d / %d" % [GameState.exp, GameState.exp_to_next()])
	_ui.set_text("txt_att", str(GameState.attack_power()))
	_ui.set_text("txt_def", str(GameState.defense()))
	_ui.set_text("txt_baoji", "%d %%" % roundi(GameState.crit() * 100))
	_ui.set_text("txt_sb", "%d %%" % roundi(GameState.miss() * 100))
	_ui.set_text("txt_hx", str(GameState.hp_regen()))
	_ui.set_text("txt_hl", str(GameState.mp_regen()))
	_ui.set_text("txt_lh", str(GameState.souls))   # no padding space: the gradient caption's value box follows the text now
	_ui.set_text("txt_zg", str(GameState.merit))
	_ui.show_frame("levelmc", clampi(GameState.level - 1, 0, 39))
	(_ui.get_piece("exp_progress") as Range).value = float(GameState.exp) / maxf(GameState.exp_to_next(), 1.0)

# ------------------------------------------------------------------ actions

## Item menu: 装备 / 出售 (the original's 赠送 is a 2P feature, not made), or for the 道具 page: 使用 / 丢弃.
## A row shows its second frame when unavailable.
func _on_bag_click(icon: Control, index: int) -> void:
	_close_menu()
	_hide_tip()
	_menu_index = index
	var item := GameState.bag[index]
	var d := GameState.item_data(item)
	var enabled := {"bzb": GameState.can_wear(item), "bmd": true}
	var moon: bool = item.id == EquipmentCatalog.get_catalog().moon.cake   # 小月饼: the menu also exchanges them
	if TABS[_tab] == "item":
		enabled = {"buse": GameState.usable(item), "bthrow": true}
		if moon:
			enabled.merge({"sbmooncake": true, "smoonweapon": true})
	_menu = UiLayout.create("item_menu_zq" if moon else "item_menu" if TABS[_tab] == "item" else "pack_menu")
	_menu.position = icon.position + _grid.position + MENU_OFFSET
	if moon:
		_menu.position.y = minf(_menu.position.y, Layers.VIEW.y - MOON_MENU_HEIGHT)
	add_child(_menu)
	PadNav.modal(_menu)
	_menu.button_pressed.connect(_menu_action)
	for p in enabled:
		_menu.show_frame(p, 0 if enabled[p] else 1)
		if enabled[p]:
			_highlight_on_hover(_menu.make_clickable(p), _menu.get_piece(p))

## Rows light up under the mouse. (The click area is the art's own bounds: the rows' origins are their centres.)
func _highlight_on_hover(hit: Control, art: Node2D) -> void:
	hit.mouse_entered.connect(func(): art.modulate = Color(1.25, 1.25, 1.25))
	hit.mouse_exited.connect(func(): art.modulate = Color.WHITE)

func _menu_action(piece: String) -> void:
	var idx := _menu_index
	_close_menu()
	match piece:
		"bzb":
			GameState.wear(idx)
			Snd.ui()
		"bmd":
			var d := GameState.item_data(GameState.bag[idx])
			if GameState.sell(idx):
				Snd.ui()
				_flash_tip("出售 %s，灵魂 +%d" % [d.display_name, d.value])
		"buse":
			_flash_tip(GameState.use_item(idx))
		"bthrow":
			GameState.discard(idx)
		"sbmooncake", "smoonweapon":
			_flash_tip(GameState.exchange_moon_cake(piece == "smoonweapon"))

func _on_worn_click(_icon: Control, slot: StringName) -> void:
	if not GameState.take_off(slot):
		_flash_tip("背包已满")

func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	_menu_index = -1

# ------------------------------------------------------------------ tooltip

func _show_tip(item: Item, at: Control) -> void:
	_tip.show_for(item, at, CELL)

func _hide_tip() -> void:
	if _tip:
		_tip.visible = false

func _flash_tip(text: String) -> void:
	Toast.show_on(self, text)
