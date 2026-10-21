class_name ShopScreen
extends CanvasLayer
## 商城 (export.microshop.Micropayment): six goods per page, pages 全部 / 道具 / 个性, bought with 功勋.
## Each good (ShopThing) has a count (BtnMore / BtnLess) and a buy button that asks for confirmation (SumInterface).

const PAGES := {"BtnEquipTab": ["item", "look"], "BtnItemTab": ["item"], "BtnFashionTab": ["look"]}

var _ui: UiLayout
var _things: Array[UiLayout] = []
var _counts: Array[int] = []
var _goods: Array = []          ## ids on the current tab
var _tab := "BtnEquipTab"
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
	HeroPortrait.build(_ui)
	var per_page := int(EquipmentCatalog.get_catalog().shop.per_page)
	for i in per_page:
		var st := _ui.piece("Thing%d" % (i + 1)) as Node2D   # the art's goods mark where the live ones go
		var t := UiLayout.create("shop_thing")
		t.position = st.position
		st.visible = false
		t.button_pressed.connect(_on_thing_button.bind(i))
		add_child(t)
		_things.append(t)
		_counts.append(1)
	_icons = Control.new()
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icons)
	_tip = ItemTip.new()
	add_child(_tip)
	_show_tab("BtnEquipTab")
	UiFade.fade_in(self)

func close() -> void:
	UiFade.close(self)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()

func _on_button(b: String) -> void:
	if _confirm:
		return
	match b:
		"BtnBack":
			close()
		"BtnPrevPage":
			_page = maxi(_page - 1, 0)
			_refresh()
		"BtnNextPage":
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
		for id: String in pages[p]:   # outfits of the other characters are not sold to this one
			var u := EquipmentCatalog.find(id).user
			if u == "" or u == GameState.hero_data.character:
				_goods.append(id)
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
		"BtnMore":
			_counts[i] = _counts[i] + 1 if stacks else 1
		"BtnLess":
			_counts[i] = maxi(_counts[i] - 1, 1)
		"BtnBuy":
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
	(c.piece("Message") as RichTextLabel).text = "[center]购买 [color=#%s]%s[/color] × %d\n需要 %d 功勋[/center]" % [
		d.color.to_html(false), d.display_name, _counts[i], cost]
	PadNav.modal(c)
	c.button_pressed.connect(func(b):
		_confirm = null
		c.queue_free()
		if b == "BtnOk":
			Toast.show_on(self, Forge.buy(id, _counts[i]))
			_counts[i] = 1
			_refresh())
	add_child(c)
	_confirm = c

func _refresh() -> void:
	_tip.visible = false
	_ui.set_text("PageText", "%d/%d" % [_page + 1, _page_count()])
	_ui.set_text("Money", "0")
	_ui.set_text("Merit", str(GameState.merit))
	for c in _icons.get_children():
		c.queue_free()
	for i in _things.size():
		var t := _things[i]
		var id := _id_at(i)
		var d := EquipmentCatalog.find(id) if id != "" else null
		t.visible = d != null
		if d == null:
			continue
		t.set_text("ItemName", d.display_name)
		(t.piece("ItemName") as Label).add_theme_color_override("font_color", d.color)
		t.set_text("Price", "%d功勋" % Forge.price(id))
		t.set_text("Count", str(_counts[i]))
		var cell := UiLayout.create("pack_cell")
		cell.position = t.position + Vector2(4, 5)
		_icons.add_child(cell)
		var item := GameState.make_item(id)
		var icon := ItemIcon.create(item, 50.0).place(cell.position)
		icon.mouse_entered.connect(func(): _tip.show_for(item, icon))
		icon.mouse_exited.connect(func(): _tip.visible = false)
		PadNav.mark(icon)   # reachable with the pad for its tooltip
		_icons.add_child(icon)
	move_child(_tip, -1)
