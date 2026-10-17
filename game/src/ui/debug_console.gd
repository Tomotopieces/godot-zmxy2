class_name DebugConsole
extends CanvasLayer
## Test console, toggled with ~ anywhere in the game (title, map, stage). Pauses the game while open. Three tabs:
##  - items: every item of the catalogue; clicking one puts a copy into the bag (ignoring capacity and the one-per-player rule);
##  - teleport: jump to any stage (its boss room included);
##  - boss fight: fight one boss alone in a single-screen arena (the ground and sky of stage 1, no scenery).

const TYPES := [["全部", ""], ["武器", "weapon"], ["防具", "cloth"], ["饰品", "accessory"], ["法宝", "treasure"],
	["翅膀", "wing"], ["时装", "fashion"], ["道具", "item"]]
const TYPE_ORDER := ["weapon", "cloth", "accessory", "treasure", "wing", "fashion", "item"]
const TYPE_NAMES := {"weapon": "武器", "cloth": "防具", "accessory": "饰品", "treasure": "法宝", "wing": "翅膀", "fashion": "时装", "item": "道具"}
const PANEL := Rect2(120, 40, 700, 510)
enum Mode { ITEMS, TELEPORT, BOSS }
const MODES := [["物品", Mode.ITEMS], ["传送", Mode.TELEPORT], ["Boss 战", Mode.BOSS]]
## [stage, what is there]: the stage rooms, with the boss each one ends on
const STAGES := [
	[Vector2i(1, 1), "鬼城 · 守夜人"], [Vector2i(1, 2), "无常巷 · 黑白无常"], [Vector2i(1, 3), "鬼门关"],
	[Vector2i(2, 1), "秦广王"], [Vector2i(2, 2), "判官"], [Vector2i(2, 3), "阎罗王"],
	[Vector2i(3, 1), "忘川河"], [Vector2i(3, 2), "夜叉"], [Vector2i(3, 3), "孟婆"],
	[Vector2i(4, 1), "转轮王"], [Vector2i(5, 1), "白骨精"], [Vector2i(6, 1), "牛魔谷 · 红孩儿"],
	[Vector2i(7, 1), "刑天"], [Vector2i(8, 1), "楚江王"], [Vector2i(9, 1), "宋帝王"],
	[Vector2i(10, 1), "螺旋地狱 · 大厅"], [Vector2i(10, 2), "螺旋地狱 · 五官王"], [Vector2i(10, 3), "螺旋地狱 · 卞城王"],
	[Vector2i(10, 4), "螺旋地狱 · 泰山王"], [Vector2i(10, 5), "螺旋地狱 · 都市王"], [Vector2i(10, 6), "螺旋地狱 · 平等王"],
	[Vector2i(11, 1), "劈天斧 / 风神盾（国庆活动关）"]]

var _list: VBoxContainer
var _search: LineEdit
var _type := ""
var _mode := Mode.ITEMS
var _type_bar: HBoxContainer
var _bosses: Array[MonsterData] = []
var _tip: ItemTip
var _root: Control
var _paused_before := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.size = Layers.VIEW
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Layers.VIEW
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = PANEL.position
	panel.size = PANEL.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.07, 0.96)
	sb.border_color = Color(0.75, 0.6, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "控制台（~ 或 Esc 关闭）"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	col.add_child(title)
	var modes := HBoxContainer.new()
	col.add_child(modes)
	var mode_group := ButtonGroup.new()
	for md in MODES:
		var mb := Button.new()
		mb.text = md[0]
		mb.toggle_mode = true
		mb.button_group = mode_group
		mb.button_pressed = md[1] == Mode.ITEMS
		mb.focus_mode = Control.FOCUS_NONE
		mb.pressed.connect(func():
			_mode = md[1]
			_rebuild())
		modes.add_child(mb)
	var bar := HBoxContainer.new()
	col.add_child(bar)
	_type_bar = HBoxContainer.new()
	bar.add_child(_type_bar)
	var group := ButtonGroup.new()
	for t in TYPES:
		var b := Button.new()
		b.text = t[0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t[1] == ""
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			_type = t[1]
			_rebuild())
		_type_bar.add_child(b)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索名称或 ID"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _rebuild())
	bar.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	_tip = ItemTip.new()
	_root.add_child(_tip)

func _input(e: InputEvent) -> void:
	if e.is_action_pressed("debug_console"):
		get_viewport().set_input_as_handled()
		toggle()
	elif _root.visible and e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		toggle()

func is_open() -> bool:
	return _root.visible

func toggle() -> void:
	if _root.visible:
		_root.visible = false
		_tip.visible = false
		get_tree().paused = _paused_before
		return
	_paused_before = get_tree().paused
	get_tree().paused = true
	_root.visible = true
	_rebuild()
	_search.grab_focus()

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_tip.visible = false
	_type_bar.visible = _mode == Mode.ITEMS
	match _mode:
		Mode.TELEPORT:
			_rebuild_stages()
		Mode.BOSS:
			_rebuild_bosses()
		_:
			_rebuild_items()

func _rebuild_items() -> void:
	var cat := EquipmentCatalog.get_catalog()
	var q := _search.text.strip_edges().to_lower()
	for type in TYPE_ORDER:
		if _type != "" and _type != type:
			continue
		for id: StringName in cat.items:
			var d: EquipmentData = cat.items[id]
			if String(d.type) != type:
				continue
			if q != "" and not (String(id).to_lower().contains(q) or d.display_name.to_lower().contains(q)):
				continue
			_list.add_child(_row(d))

func _row(d: EquipmentData) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 38)
	var pic := ItemIcon.create(GameState.make_item(String(d.id)), 34.0).place(Vector2(2, 2))   # as in the bag
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	b.add_theme_constant_override("h_separation", 0)
	b.text = "          %s    [%s]  %s · %s · %s" % [d.display_name, d.id, TYPE_NAMES.get(String(d.type), String(d.type)), d.quality,
		d.user if d.user != "" else "通用"]
	b.add_theme_color_override("font_color", d.color if d.color.get_luminance() > 0.25 else Color.WHITE)
	b.add_theme_color_override("font_hover_color", d.color.lightened(0.3) if d.color.get_luminance() > 0.25 else Color(1, 1, 0.7))
	var id := String(d.id)
	b.pressed.connect(func(): _give(id))
	b.mouse_entered.connect(func(): _tip.show_for(GameState.make_item(id), b, 0.0))
	b.mouse_exited.connect(func(): _tip.visible = false)
	return b

func _give(id: String) -> void:
	var item := GameState.make_item(id)
	if item == null:
		return
	GameState.add_to_bag(item, true)
	Toast.show_on(self, "已添加 %s" % GameState.item_data(item).display_name)

func _text_row(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.text = text
	b.pressed.connect(on_press)
	return b

func _rebuild_stages() -> void:
	var q := _search.text.strip_edges().to_lower()
	for e in STAGES:
		var s: Vector2i = e[0]
		var label := "%d-%d  %s" % [s.x, s.y, e[1]]
		if q == "" or label.to_lower().contains(q):
			_list.add_child(_text_row(label, func(): _teleport(s)))

## Every monster that is a boss in some room, in id order.
func _boss_list() -> Array[MonsterData]:
	if _bosses.is_empty():
		var ids: Array[int] = []
		for f in DirAccess.get_files_at("res://data/monsters"):
			var base := f.get_basename()
			if f.get_extension() == "tres" and base.begins_with("monster_") and base.count("_") == 1:
				ids.append(int(base.get_slice("_", 1)))
		ids.sort()
		for id in ids:
			var md: MonsterData = load("res://data/monsters/monster_%d.tres" % id)
			if md != null and md.is_boss:
				_bosses.append(md)
	return _bosses

func _rebuild_bosses() -> void:
	var q := _search.text.strip_edges().to_lower()
	for md in _boss_list():
		var label := "%s    [%d]" % [md.display_name, md.id]
		if q == "" or label.to_lower().contains(q):
			_list.add_child(_text_row(label, func(): _fight(md)))

## Whether a game is running (the title screen has no hero to send anywhere).
func _can_start() -> bool:
	if GameState.hero_data == null:
		Toast.show_on(self, "请先开始游戏")
		return false
	return true

func _teleport(s: Vector2i) -> void:
	if _can_start():
		toggle()
		get_parent().start_stage(s)

func _fight(md: MonsterData) -> void:
	if _can_start():
		Level.arena_boss = md
		toggle()
		get_parent().start_stage(Level.ARENA)
