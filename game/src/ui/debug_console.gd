class_name DebugConsole
extends CanvasLayer
## Test console, toggled with ~ anywhere in the game (title, map, stage). Lists every item of the catalogue;
## clicking one puts a copy into the bag (ignoring capacity and the one-per-player rule). Pauses the game while open.

const TYPES := [["全部", ""], ["武器", "weapon"], ["防具", "cloth"], ["饰品", "accessory"], ["法宝", "treasure"],
	["翅膀", "wing"], ["时装", "fashion"], ["道具", "item"]]
const TYPE_ORDER := ["weapon", "cloth", "accessory", "treasure", "wing", "fashion", "item"]
const TYPE_NAMES := {"weapon": "武器", "cloth": "防具", "accessory": "饰品", "treasure": "法宝", "wing": "翅膀", "fashion": "时装", "item": "道具"}
const PANEL := Rect2(120, 40, 700, 510)

var _list: VBoxContainer
var _search: LineEdit
var _type := ""
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
	title.text = "控制台 —— 点击物品加入背包（~ 或 Esc 关闭）"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	col.add_child(title)
	var bar := HBoxContainer.new()
	col.add_child(bar)
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
		bar.add_child(b)
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
	b.icon = d.icon
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 34)
	b.custom_minimum_size = Vector2(0, 38)
	b.text = "%s    [%s]  %s · %s · %s" % [d.display_name, d.id, TYPE_NAMES.get(String(d.type), String(d.type)), d.quality,
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
