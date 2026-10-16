class_name ForgeScreen
extends CanvasLayer
## 炼丹炉 (export.strength.StrengthEquip > StrengthPack): bag grid on the right (装备 / 道具 / 时装 pages),
## 强化 or 合成 page on the left. Clicking a bag item puts it into the matching slot; clicking a slot gives it back.
## Opened from the stage map. Rules live in Forge.

const GRID_ORIGIN := Vector2(522, 142)
const GRID_COLS := 5
const CELL := 50.0
const CELL_GAP := 7.0
const TABS := {"btn_zb": "equip", "btn_dj": "item", "btn_sz": "look"}
const STONE_SLOTS := ["qhmc1", "qhmc2", "qhmc3"]
const MATERIAL_SLOTS := ["material1", "material2", "material3"]

var _pack: UiLayout
var _page: UiLayout
var _fusion := false
var _tab := "btn_zb"
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
	back.show_frame("player1", 1)       # Wukong selected; the other characters are not in this game
	back.set_visible_piece("player2", false)
	back.set_visible_piece("player3", false)
	back.button_pressed.connect(func(b): if b == "btnback": close())
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

func close() -> void:
	_return_all()
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()

func _on_button(b: String) -> void:
	match b:
		"strengthbtn":
			_show_page(false)
		"mixturebtn":
			_show_page(true)
		"qhbtn":
			_do_strengthen()
		"rlbtn":
			_do_fusion()
		"btn_help":
			_show_help()
		_:
			if TABS.has(b):
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
	for s in (MATERIAL_SLOTS + ["produce"] if fusion else ["zbmc", "luckmc", "baodimc"] + STONE_SLOTS):
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
		slot = "zbmc"
	elif d.stone > 0:
		for s in STONE_SLOTS:
			if _slots[s] == null:
				slot = s
				break
	elif d.charm == &"luck":
		slot = "luckmc"
	elif d.charm == &"keep":
		slot = "baodimc"
	if slot == "":
		return
	_produce = null
	if _slots[slot] != null:
		GameState.add_to_bag(_slots[slot], true)
		index = GameState.bag.find(item)
	_slots[slot] = GameState.take_at(index)
	_refresh()

func _take(slot: String) -> void:
	if slot == "produce":
		return
	GameState.add_to_bag(_slots[slot], true)
	_slots[slot] = null
	_refresh()

## Leaving the page / screen: everything in the slots goes back to the bag.
func _return_all() -> void:
	for s in _slots:
		if s != "produce" and _slots[s] != null:
			GameState.add_to_bag(_slots[s], true)
			_slots[s] = null

func _stones() -> Array:
	return STONE_SLOTS.map(func(s): return _slots[s]).filter(func(it): return it != null)

func _do_strengthen() -> void:
	var equip: Item = _slots.get("zbmc")
	var stones := _stones()
	if equip == null or stones.is_empty():
		return
	var ok := Forge.strengthen(equip, stones, _slots.luckmc != null, _slots.baodimc != null)
	# the stones and charms are used up either way; the equipment goes back to the bag
	for s in STONE_SLOTS + ["luckmc", "baodimc"]:
		_slots[s] = null
	GameState.add_to_bag(equip, true)
	_slots.zbmc = null
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
	_pack.set_text("txtlh", str(GameState.souls))
	for c in _grid.get_children():
		c.queue_free()
	var shown := GameState.tab_items(TABS[_tab])
	for k in GRID_COLS * GRID_COLS:
		var pos := Vector2(k % GRID_COLS, k / GRID_COLS) * (CELL + CELL_GAP)
		var cell := UiLayout.create("pack_cell")
		cell.position = pos
		_grid.add_child(cell)
		if k < shown.size():
			var idx: int = shown[k]
			_grid.add_child(_icon(GameState.bag[idx], pos, _put.bind(idx)))
			var n := GameState.bag[idx].n
			if n > 1:
				_grid.add_child(_count(n, pos))
	for c in _slot_icons.get_children():
		c.queue_free()
	for s in _slots:
		var it: Item = _produce if s == "produce" else _slots[s]
		if it != null:
			_slot_icons.add_child(_icon(it, _page.piece_position(s), _take.bind(s)))
	if _fusion:
		var mats: Array = MATERIAL_SLOTS.map(func(s): return _slots[s]).filter(func(m): return m != null)
		var r := Forge.recipe_for(mats)
		var d := EquipmentCatalog.find(r.get("out", ""))
		_page.set_text("txt_name", d.display_name if d else "")
		_page.set_text("txt_needlh", str(Forge.fusion_cost(r)) if d else "")
		_page.set_text("txt_success", "%d%%" % roundi(Forge.fusion_chance(r) * 100) if d else "")
		if d and _produce == null:
			var pv := TextureRect.new()
			pv.texture = d.icon
			pv.position = _page.piece_position("preview")
			pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_slot_icons.add_child(pv)
	else:
		var equip: Item = _slots.zbmc
		var p := 0.0 if equip == null else Forge.success_chance(equip, _stones(), _slots.luckmc != null)
		_page.set_text("txt_success", "%d%%" % floori(p * 100))
		_page.set_text("txt_needlh", "0")

func _icon(item: Item, pos: Vector2, on_click: Callable) -> TextureRect:
	var t := TextureRect.new()
	var d := GameState.item_data(item)
	var ground := d.ground_icon != null
	t.texture = d.ground_icon if ground else d.icon
	t.position = pos if ground else pos + Vector2(0, -2)
	t.size = Vector2(CELL, CELL)
	if ground:
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	t.mouse_entered.connect(_show_tip.bind(item, t))
	t.mouse_exited.connect(_hide_tip)
	t.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())
	PadNav.mark(t)
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
	PadNav.modal(h)
	h.button_pressed.connect(func(_b): h.queue_free())
	add_child(h)

func _notice(text: String) -> void:
	Toast.show_on(self, text)

func _show_tip(item: Item, at: Control) -> void:
	_tip.show_for(item, at, CELL)

func _hide_tip() -> void:
	if _tip:
		_tip.visible = false
