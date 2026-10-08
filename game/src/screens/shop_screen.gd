class_name ShopScreen
extends CanvasLayer
## 商城 (export.microshop.Micropayment): six goods per page, pages 全部 / 道具 / 个性, bought with 功勋.
## Each good (ShopThing) has a count (btn_up / btn_down) and a buy button that asks for confirmation (SumInterface).

const PAGES := {"btn_buyzb": ["item", "look"], "btn_buydj": ["item"], "btn_buygx": ["look"]}

var _ui: UiLayout
var _things: Array[UiLayout] = []
var _counts: Array[int] = []
var _goods: Array = []          ## ids on the current tab
var _tab := "btn_buyzb"
var _page := 0
var _icons: Control
var _tip: ItemTip
var _confirm: Control

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.size = Layers.VIEW
	add_child(dim)
	_ui = UiLayout.create("shop")
	_ui.button_pressed.connect(_on_button)
	add_child(_ui)
	_ui.show_frame("personmc", 0)
	for p in ["btn_play2", "btn_cz"]:
		_ui.set_visible_piece(p, false)
	var per_page := int(EquipmentCatalog.get_catalog().shop.per_page)
	for i in per_page:
		var st := "st%d" % i
		var t := UiLayout.create("shop_thing")
		t.position = _ui.piece_position(st)
		_ui.set_visible_piece(st, false)
		t.button_pressed.connect(_on_thing_button.bind(i))
		add_child(t)
		_things.append(t)
		_counts.append(1)
	_icons = Control.new()
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icons)
	_tip = ItemTip.new()
	add_child(_tip)
	_show_tab("btn_buyzb")

func close() -> void:
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()

func _on_button(b: String) -> void:
	if _confirm:
		return
	match b:
		"btn_back":
			close()
		"btn_upPage":
			_page = maxi(_page - 1, 0)
			_refresh()
		"btn_nextPage":
			_page = mini(_page + 1, _page_count() - 1)
			_refresh()
		_:
			if PAGES.has(b):
				_show_tab(b)

func _show_tab(b: String) -> void:
	_tab = b
	_page = 0
	_goods.clear()
	var pages: Dictionary = EquipmentCatalog.get_catalog().shop.pages
	for p in PAGES[b]:
		_goods.append_array(pages[p])
	_refresh()

func _page_count() -> int:
	return maxi(ceili(_goods.size() / float(_things.size())), 1)

func _id_at(i: int) -> String:
	var k := _page * _things.size() + i
	return _goods[k] if k < _goods.size() else ""

func _on_thing_button(b: String, i: int) -> void:
	if _confirm or _id_at(i) == "":
		return
	var stacks := EquipmentCatalog.find(_id_at(i)).stacks()
	match b:
		"btn_up":
			_counts[i] = _counts[i] + 1 if stacks else 1
		"btn_down":
			_counts[i] = maxi(_counts[i] - 1, 1)
		"btn_buy":
			_ask(i)
			return
	_refresh()

## SumInterface: name, count and total; 确定 buys, 返回 cancels.
func _ask(i: int) -> void:
	var id := _id_at(i)
	var cost := Forge.price(id) * _counts[i]
	if GameState.merit < cost:
		Toast.show_on(self, "功勋不足！")
		return
	var c := UiLayout.create("shop_confirm")
	var d := EquipmentCatalog.find(id)
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.text = "[center]购买 [color=#%s]%s[/color] × %d\n需要 %d 功勋[/center]" % [d.color.to_html(false), d.display_name, _counts[i], cost]
	l.position = Vector2(330, 245)
	l.size = Vector2(280, 60)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	c.button_pressed.connect(func(b):
		_confirm = null
		c.queue_free()
		if b == "btn_ok":
			Toast.show_on(self, Forge.buy(id, _counts[i]))
			_counts[i] = 1
			_refresh())
	add_child(c)
	_confirm = c

func _refresh() -> void:
	_tip.visible = false
	_ui.set_text("txt_page", "%d/%d" % [_page + 1, _page_count()])
	_ui.set_text("txt_money", "0")
	_ui.set_text("txt_gx", str(GameState.merit))
	for c in _icons.get_children():
		c.queue_free()
	for i in _things.size():
		var t := _things[i]
		var id := _id_at(i)
		var d := EquipmentCatalog.find(id) if id != "" else null
		t.visible = d != null
		if d == null:
			continue
		t.set_text("txt_name", d.display_name)
		(t.get_piece("txt_name") as Label).add_theme_color_override("font_color", d.color)
		t.set_text("txt_price", "%d功勋" % Forge.price(id))
		t.set_text("txt_num", str(_counts[i]))
		var cell := UiLayout.create("pack_cell")
		cell.position = t.position + Vector2(4, 5)
		_icons.add_child(cell)
		var icon := TextureRect.new()
		icon.texture = d.icon
		icon.position = cell.position + Vector2(0, -2)
		icon.size = Vector2(50, 50)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		var item := GameState.make_item(id)
		icon.mouse_entered.connect(func(): _tip.show_for(item, icon))
		icon.mouse_exited.connect(func(): _tip.visible = false)
		_icons.add_child(icon)
	move_child(_tip, -1)
