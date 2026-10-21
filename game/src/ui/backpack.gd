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
const SLOT_NODES := {&"weapon": "WeaponSlot", &"cloth": "ClothSlot", &"accessory": "AccessorySlot", &"treasure": "TreasureSlot",
	&"fashion": "FashionSlot", &"wing": "WingSlot"}
const TABS := {"BtnZhuangBei": "equip", "BtnDaoJu": "item", "BtnShiZhuang": "look"}   ## page button -> bag page

var _ui: UiLayout
var _grid: Control
var _worn: Control
var _tip: ItemTip
var _menu: UiLayout
var _menu_index := -1
var _tab := "BtnZhuangBei"
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
	HeroPortrait.build(_ui)
	_ui.button_pressed.connect(_on_button)
	_grid = _ui.piece("Grid")   # the scene's own 5x5 cells: nothing is created here

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
	if b == "BtnClose":
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
	var icons := []
	for cell in _grid.get_children():
		if not _is_cell(cell):
			continue
		var pos: Vector2 = (cell as Control).position
		if k < shown.size():
			var idx: int = shown[k]
			icons.append(_icon(GameState.bag[idx], pos, _on_bag_click.bind(idx)))
			_grid.add_child(icons[-1])
			var n := GameState.bag[idx].n
			if n > 1:
				_grid.add_child(_count_label(n, pos))
		k += 1
	PadFocus.link_grid(icons, GRID_COLS)
	# worn gear on the slot frames (an empty slot keeps its caption, an occupied one hides it)
	for slot in SLOT_NODES:
		var item: Item = GameState.worn[slot]
		var piece: Node2D = _ui.piece(SLOT_NODES[slot])
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
	t.focus_entered.connect(_show_tip.bind(item, t))   # the pad's focus shows the tooltip like a hover
	t.focus_exited.connect(_hide_tip)
	t.focus_mode = Control.FOCUS_ALL
	t.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_released("ui_accept"):
			on_click.call(t))
	return t

func _fill_stats() -> void:
	var h: Hero = Level.current.hero if Level.current else null
	var hp := h.hp if h else GameState.max_hp()
	var mp := h.mp if h else GameState.max_mp()
	_ui.set_text("HeroName", GameState.hero_data.title)
	_stat("StatHp", "%d / %d" % [hp, GameState.max_hp()])
	_stat("StatMp", "%d / %d" % [mp, GameState.max_mp()])
	_stat("StatExp", "%d / %d" % [GameState.exp, GameState.exp_to_next()])
	_stat("StatAtk", str(GameState.attack_power()))
	_stat("StatDef", str(GameState.defense()))
	_stat("StatCrit", "%d %%" % roundi(GameState.crit() * 100))
	_stat("StatMiss", "%d %%" % roundi(GameState.miss() * 100))
	_stat("StatHpRegen", str(GameState.hp_regen()))
	_stat("StatMpRegen", str(GameState.mp_regen()))
	_stat("LingHun", str(GameState.souls))
	_stat("GongXun", str(GameState.merit))
	(_ui.piece("Level") as IconSet).index = clampi(GameState.level - 1, 0, 39)
	(_ui.piece("ExpProgress") as Range).value = float(GameState.exp) / maxf(GameState.exp_to_next(), 1.0)

func _stat(row: String, value: String) -> void:
	_ui.piece(row).set_value(value)

# ------------------------------------------------------------------ actions

## Item menu (scenes/ui/item_menu.tscn, the same for every page): 装备 / 出售 (the original's 赠送 is a 2P feature, not
## made), or on the 道具 page 使用 / 丢弃 and the 小月饼 exchanges. Only the item's buttons show; unavailable ones are
## disabled.
func _on_bag_click(icon: Control, index: int) -> void:
	_close_menu()
	_hide_tip()
	_menu_index = index
	var item := GameState.bag[index]
	var enabled := {"Wear": GameState.can_wear(item), "Sell": true}
	if TABS[_tab] == "item":
		enabled = {"Use": GameState.usable(item), "Throw": true}
		if item.id == EquipmentCatalog.get_catalog().moon.cake:   # 小月饼: the menu also exchanges them
			enabled.merge({"BigMooncake": true, "MoonWeapon": true})
	_menu = UiLayout.create("item_menu")
	for b: Button in _menu.piece("Buttons").get_children():
		b.visible = enabled.has(String(b.name))
		b.disabled = not enabled.get(String(b.name), false)
	add_child(_menu)
	_menu.reset_size()   # the frame shrinks to the shown buttons (fonts are only known in the tree)
	_menu.position = icon.position + _grid.position + MENU_OFFSET
	_menu.position.y = minf(_menu.position.y, Layers.VIEW.y - _menu.size.y)
	PadFocus.modal(_menu)
	_menu.button_pressed.connect(_menu_action)

func _menu_action(action: String) -> void:
	var idx := _menu_index
	_close_menu()
	match action:
		"Wear":
			GameState.wear(idx)
			Snd.ui()
		"Sell":
			var d := GameState.item_data(GameState.bag[idx])
			if GameState.sell(idx):
				Snd.ui()
				_flash_tip("出售 %s，灵魂 +%d" % [d.display_name, d.value])
		"Use":
			_flash_tip(GameState.use_item(idx))
		"Throw":
			GameState.discard(idx)
		"BigMooncake", "MoonWeapon":
			_flash_tip(GameState.exchange_moon_cake(action == "MoonWeapon"))

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
