class_name ForgeScreen
extends CanvasLayer
## 炼丹炉 (export.strength.StrengthEquip > StrengthPack): bag grid on the right (装备 / 道具 / 时装 pages),
## 强化 or 合成 page on the left. Clicking a bag item puts it into the matching slot; clicking a slot gives it back.
## Opened from the stage map. Rules live in Forge.

const GRID_ORIGIN := Vector2(522, 142)
const GRID_COLS := 5
const CELL := 50.0
const CELL_GAP := 7.0
const TABS := {"BtnZhuangBei": "equip", "BtnDaoJu": "item", "BtnShiZhuang": "look"}
const STONE_SLOTS := ["Stone1", "Stone2", "Stone3"]
const MATERIAL_SLOTS := ["Material1", "Material2", "Material3"]

var _pack: UiLayout
var _page: UiLayout
var _fusion := false
var _tab := "BtnZhuangBei"
var _grid: Control
var _slot_icons: Control
var _slots := {}          ## slot piece -> Item in it (null = empty)
var _produce: Item        ## last fusion product (shown until something changes)
var _tip: ItemTip

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.size = Layers.VIEW
	add_child(dim)
	var back := UiLayout.create("forge")
	back.button_pressed.connect(func(b): if b == "BtnBack": close())
	add_child(back)
	_pack = UiLayout.create("forge_pack")
	_pack.button_pressed.connect(_on_button)
	add_child(_pack)
	_grid = Control.new()
	_grid.position = GRID_ORIGIN
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	_tip = ItemTip.new()
	add_child(_tip)
	_show_page(false)
	UiFade.fade_in(self)

func close() -> void:
	_return_all()
	UiFade.close(self)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
	elif e is InputEventJoypadButton and e.pressed and e.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		# LB / RB: the previous / next bag page, as in the backpack
		get_viewport().set_input_as_handled()
		var pages := TABS.keys()
		var d := -1 if e.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
		_on_button(pages[posmod(pages.find(_tab) + d, pages.size())])

func _process(_dt: float) -> void:
	for icon in ["LbIcon", "RbIcon"]:
		_pack.piece(icon).visible = PadFocus.pad_last   # pad hints only while the pad is used

func _on_button(b: String) -> void:
	match b:
		"StrengthenTab":
			_show_page(false)
		"FusionTab":
			_show_page(true)
		"BtnStrengthen":
			_do_strengthen()
		"BtnFuse":
			_do_fusion()
		"BtnHelp":
			_show_help()
		_:
			if TABS.has(b):
				Snd.ui()
				_tab = b
				_refresh()

func _show_page(fusion: bool) -> void:
	_return_all()
	_fusion = fusion
	if _page:
		_page.queue_free()
	_page = UiLayout.create("forge_fusion" if fusion else "forge_strength")
	_page.button_pressed.connect(_on_button)
	add_child(_page)
	move_child(_page, _grid.get_index())
	if _slot_icons:
		_slot_icons.queue_free()
	_slot_icons = Control.new()
	_slot_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_icons)
	move_child(_tip, -1)
	_slots.clear()
	for s in (MATERIAL_SLOTS + ["Product"] if fusion else ["Equipment", "Luck", "Guarantee"] + STONE_SLOTS):
		_slots[s] = null
	_refresh()

# ------------------------------------------------------------------ slots

## Bag click: the item goes into the first fitting slot (one copy of a stack).
func _put(index: int) -> void:
	var item := GameState.bag[index]
	var d := GameState.item_data(item)
	var slot := ""
	if _fusion:
		for s in MATERIAL_SLOTS:
			if _slots[s] == null:
				slot = s
				break
	elif Forge.can_strengthen(item):
		slot = "Equipment"
	elif d.stone > 0:
		for s in STONE_SLOTS:
			if _slots[s] == null:
				slot = s
				break
	elif d.charm == &"luck":
		slot = "Luck"
	elif d.charm == &"keep":
		slot = "Guarantee"
	if slot == "":
		return
	_produce = null
	if _slots[slot] != null:
		GameState.add_to_bag(_slots[slot], true)
		index = GameState.bag.find(item)
	_slots[slot] = GameState.take_at(index)
	_refresh()

func _take(slot: String) -> void:
	if slot == "Product":
		return
	GameState.add_to_bag(_slots[slot], true)
	_slots[slot] = null
	_refresh()

## Leaving the page / screen: everything in the slots goes back to the bag.
func _return_all() -> void:
	for s in _slots:
		if s != "Product" and _slots[s] != null:
			GameState.add_to_bag(_slots[s], true)
			_slots[s] = null

func _stones() -> Array:
	return STONE_SLOTS.map(func(s): return _slots[s]).filter(func(it): return it != null)

func _do_strengthen() -> void:
	var equip: Item = _slots.get("Equipment")
	var stones := _stones()
	if equip == null or stones.is_empty():
		return
	var ok := Forge.strengthen(equip, stones, _slots.Luck != null, _slots.Guarantee != null)
	# the stones and charms are used up either way; the equipment goes back to the bag
	for s in STONE_SLOTS + ["Luck", "Guarantee"]:
		_slots[s] = null
	GameState.add_to_bag(equip, true)
	_slots.Equipment = null
	_notice("强化成功" if ok else "强化失败")
	_refresh()

func _do_fusion() -> void:
	var mats: Array = MATERIAL_SLOTS.map(func(s): return _slots[s])
	var recipe := Forge.recipe_for(mats.filter(func(m): return m != null))
	if recipe.is_empty():
		return
	var cost := Forge.fusion_cost(recipe)
	if GameState.souls < cost:
		_notice("灵魂值不够")
		return
	GameState.souls -= cost
	var out := Forge.produce(recipe, mats)
	for s in MATERIAL_SLOTS:
		_slots[s] = null
	if out == null:
		_notice("合成失败")
	else:
		GameState.add_to_bag(out, true)
		_produce = out
		_notice("合成成功")
	GameState.profile_changed.emit()
	_refresh()

# ------------------------------------------------------------------ view

func _refresh() -> void:
	_hide_tip()
	_pack.set_text("Souls", str(GameState.souls))
	for c in _grid.get_children():
		c.queue_free()
	var shown := GameState.tab_items(TABS[_tab])
	var icons := []
	for k in GRID_COLS * GRID_COLS:
		var pos := Vector2(k % GRID_COLS, k / GRID_COLS) * (CELL + CELL_GAP)
		var cell := UiLayout.create("pack_cell")
		cell.position = pos
		_grid.add_child(cell)
		if k < shown.size():
			var idx: int = shown[k]
			icons.append(_icon(GameState.bag[idx], pos, _put.bind(idx)))
			_grid.add_child(icons[-1])
			var n := GameState.bag[idx].n
			if n > 1:
				_grid.add_child(_count(n, pos))
	PadFocus.link_grid(icons, GRID_COLS)
	for c in _slot_icons.get_children():
		c.queue_free()
	for s in _slots:
		var it: Item = _produce if s == "Product" else _slots[s]
		if it != null:
			_slot_icons.add_child(_icon(it, (_page.piece(s) as Node2D).position, _take.bind(s)))
	if _fusion:
		var mats: Array = MATERIAL_SLOTS.map(func(s): return _slots[s]).filter(func(m): return m != null)
		var r := Forge.recipe_for(mats)
		var d := EquipmentCatalog.find(r.get("out", ""))
		_page.set_text("ProductName", d.display_name if d else "")
		_page.set_text("SoulCost", str(Forge.fusion_cost(r)) if d else "")
		_page.set_text("SuccessRate", "%d%%" % roundi(Forge.fusion_chance(r) * 100) if d else "")
		if d and _produce == null:
			var pv := TextureRect.new()
			pv.texture = d.icon
			pv.position = (_page.piece("Preview") as Node2D).position
			pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_slot_icons.add_child(pv)
	else:
		var equip: Item = _slots.Equipment
		var p := 0.0 if equip == null else Forge.success_chance(equip, _stones(), _slots.Luck != null)
		_page.set_text("SuccessRate", "%d%%" % floori(p * 100))
		_page.set_text("SoulCost", "0")

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
			on_click.call())
	return t

func _count(n: int, pos: Vector2) -> Label:
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

func _show_help() -> void:
	var h := UiLayout.create("forge_help")
	h.position = Vector2(102, 40)
	PadFocus.modal(h)
	h.button_pressed.connect(func(_b): h.queue_free())
	add_child(h)

func _notice(text: String) -> void:
	Toast.show_on(self, text)

func _show_tip(item: Item, at: Control) -> void:
	_tip.show_for(item, at, CELL)

func _hide_tip() -> void:
	if _tip:
		_tip.visible = false
