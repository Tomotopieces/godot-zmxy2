class_name ActivityPanel
extends CanvasLayer
## 活动 (SelectPLace.huodongbtn -> export.huodong.ChineseValentinesDay): the past events of the original.
##   七夕: 9-1 宋帝王, once a day; 宋帝王 pays 10 功勋 when he falls, and the 喜鹊 / 水牛 he frees drop 幸运的喜鹊 / 顽固的水牛.
##   国庆: 11-1 劈天斧 / 风神盾 (one of the two), once a day; each leaves a 1级强化石, 劈天斧 gives 攻击 +100 and 风神盾
##         防御 +50 for an hour. The way on is 刑天 -> 战神刑天 (刑天之翼).
##   中秋: no stage - every boss drops 小月饼 (the bag exchanges them); this page explains it and switches it on and off.
## The 七夕 page is the original picture. The other two pages had no picture of their own in the files (国庆 follows the
## later "战神刑天来袭" window), so they are laid out from the stage art, the monsters' own rigs and the items' icons.

signal play(stage: Vector2i)

const PAGES := [
	{"id": "qixi", "stage": Vector2i(9, 1)},
	{"id": "guoqing", "stage": Vector2i(11, 1)},
	{"id": "zhongqiu"},
]
const FRAME := Rect2(85, 32, 773, 520)   ## the picture's frame, in layout space
const DONE_TEXT := "您已经参加过活动了，请明天再来吧"
const ORANGE := Color("e8581a")
const BLUE := Color("4a63c8")
const DARK_BLUE := Color("1c2260")

var _ui: UiLayout
var _art: Node
var _pages: Array = []
var _page := 0
var _label: Label

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Layers.VIEW
	add_child(dim)
	_ui = UiLayout.create("valentines")
	add_child(_ui)
	_art = _ui.get_child(0)   # the 七夕 picture; GO and close are drawn over it
	_pages = [null, _build_guoqing(), _build_zhongqiu()]
	for i in [1, 2]:
		_ui.add_child(_pages[i])
		_ui.move_child(_pages[i], 1)
	_ui.button_pressed.connect(_on_button)
	for side in [[-1, 38.0, "◀"], [1, 868.0, "▶"]]:
		var b := Button.new()
		b.text = side[2]
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(side[1], 262)
		b.size = Vector2(34, 66)
		b.pressed.connect(_turn.bind(side[0]))
		add_child(b)
	_label = Label.new()
	_label.position = Vector2(0, 556)
	_label.size = Vector2(Layers.VIEW.x, 28)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	_show_page()

func _turn(d: int) -> void:
	_page = posmod(_page + d, PAGES.size())
	_show_page()

func _show_page() -> void:
	_art.visible = _page == 0
	for i in _pages.size():
		if _pages[i]:
			_pages[i].visible = i == _page
	_ui.get_piece("btn_go").visible = PAGES[_page].has("stage")
	_label.text = "%d / %d" % [_page + 1, PAGES.size()]

func _on_button(b: String) -> void:
	if b == "btn_x":
		queue_free()
		return
	if b != "btn_go" or not PAGES[_page].has("stage"):
		return
	var p: Dictionary = PAGES[_page]
	if GameState.activity_done(p.id):
		Toast.show_on(self, DONE_TEXT)
		return
	GameState.mark_activity(p.id)
	play.emit(p.stage)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()
	elif e.is_action_pressed("move_left"):
		_turn(-1)
	elif e.is_action_pressed("move_right"):
		_turn(1)

# ------------------------------------------------------------------ pieces

func _box(rect: Rect2, fill: Color, border: Color, radius: int, width: int) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _text(text: String, pos: Vector2, size: Vector2, font: int, color: Color, outline: Color, outline_size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = size
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", outline_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A dashed rectangle (the stitched border of the original windows).
func _dashes(rect: Rect2, color: Color) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var pts := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position]
		for i in 4:
			c.draw_dashed_line(pts[i], pts[i + 1], color, 2.0, 9.0))
	return c

## The striped ribbon across the top-right corner.
func _ribbon(corner: Vector2, a: Color, b: Color) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		for k in 5:
			var c0 := 26.0 + 11.0 * k
			var c1 := c0 + 11.0
			c.draw_colored_polygon(PackedVector2Array([corner + Vector2(-c1, 0), corner + Vector2(-c0, 0), corner + Vector2(0, c0), corner + Vector2(0, c1)]), a if k % 2 == 0 else b))
	return c

## A red hint box with its little "温馨提示" tag on top.
func _tip_box(page: Control, rect: Rect2, fill: Color, border: Color, tag_fill: Color, tag_text: Color, tag_outline: Color) -> void:
	page.add_child(_box(rect, fill, border, 12, 2))
	var tag := Rect2(rect.position.x + 14, rect.position.y - 24, 98, 30)
	page.add_child(_box(tag, tag_fill, border, 8, 2))
	page.add_child(_text("温馨提示", tag.position, tag.size, 18, tag_text, tag_outline, 3))

func _icon(id: String, pos: Vector2, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = EquipmentCatalog.find(id).icon
	t.position = pos
	t.size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _rig(id: String, pos: Vector2, scale: float, tint := Color.WHITE) -> Rig:
	var r := Rig.create(id)
	r.position = pos
	r.scale = Vector2.ONE * scale
	r.modulate = tint
	r.ready.connect(r.play.bind(&"wait"))
	return r

# ------------------------------------------------------------------ 国庆: 战神刑天来袭

func _build_guoqing() -> Control:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_box(FRAME, ORANGE, Color("3a1206"), 22, 4))
	var inner := Rect2(FRAME.position + Vector2(16, 16), FRAME.size - Vector2(32, 32))
	# the hall of 11-1 behind everything, darkened and clipped to the window
	var clip := Control.new()
	clip.position = inner.position
	clip.size = inner.size
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/activity/guoqing_bg.png")
	bg.position = -inner.position
	bg.modulate = Color(0.55, 0.42, 0.42)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(bg)
	# 战神刑天: a black shape with a red glow, huge, behind the title
	for e in [[Color(1.0, 0.18, 0.05, 0.85), Vector2(3, 3)], [Color(0.02, 0.0, 0.0), Vector2.ZERO]]:
		clip.add_child(_rig("monster81", Vector2(470, 440) - inner.position + e[1], 2.6, e[0]))
	page.add_child(clip)
	page.add_child(_box(inner, Color(0, 0, 0, 0), Color("3a1206"), 14, 3))
	page.add_child(_dashes(inner.grow(-6), Color("2a0c04")))
	page.add_child(_ribbon(Vector2(FRAME.end.x - 4, FRAME.position.y + 4), Color("e8321c"), Color("ffd23a")))
	page.add_child(_text("战神刑天来袭", Vector2(180, 52), Vector2(580, 100), 84, Color("ffc21a"), Color("5a1a06"), 14))
	# the two guardians
	for e in [["monster79", Vector2(215, 305), 1.15, "劈天斧", Vector2(150, 318)], ["monster80", Vector2(735, 290), 1.2, "风神盾", Vector2(690, 330)]]:
		page.add_child(_rig(e[0], e[1], e[2]))
		page.add_child(_text(e[3], e[4], Vector2(100, 34), 26, Color("ffd24a"), Color("3a1206"), 6))
	_tip_box(page, Rect2(106, 424, 604, 104), Color("d6431a"), Color("ffe6a0"), Color("e8761a"), Color("fff0b0"), Color("5a1a06"))
	var tip := RichTextLabel.new()
	tip.bbcode_enabled = true
	tip.scroll_active = false
	tip.position = Vector2(120, 430)
	tip.size = Vector2(580, 94)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_theme_font_size_override("normal_font_size", 17)
	tip.add_theme_color_override("default_color", Color.WHITE)
	tip.add_theme_color_override("font_outline_color", Color("5a1a06"))
	tip.add_theme_constant_override("outline_size", 4)
	tip.text = "每天只能进入一次副本，击败风神盾和劈天斧获得相应BUFF和强化石。击败刑天后出现超级BOSS战神刑天。击杀战神刑天有概率获得 [img=22]res://assets/items/xtzy.png[/img] 刑天之翼。"
	page.add_child(tip)
	return page

# ------------------------------------------------------------------ 中秋

func _build_zhongqiu() -> Control:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_box(FRAME, BLUE, DARK_BLUE, 22, 3))
	var inner := Rect2(FRAME.position + Vector2(22, 22), FRAME.size - Vector2(44, 44))
	page.add_child(_box(inner, Color("1d1b4d"), DARK_BLUE, 16, 2))
	page.add_child(_dashes(FRAME.grow(-9), DARK_BLUE))
	page.add_child(_text("中秋献礼", Vector2(110, 52), Vector2(520, 70), 56, Color("ffe27a"), Color("5a2a9a"), 10, HORIZONTAL_ALIGNMENT_LEFT))
	page.add_child(_text("绝版武器迎中秋", Vector2(110, 120), Vector2(520, 44), 30, Color("f1e4ff"), Color("5a2a9a"), 7, HORIZONTAL_ALIGNMENT_LEFT))
	var moon: Dictionary = EquipmentCatalog.get_catalog().moon
	# 小月饼 -> 大月饼 -> 绝版武器
	page.add_child(_icon(moon.cake, Vector2(120, 176), 56))
	page.add_child(_text("每个 BOSS 必掉 1 个小月饼\n在背包道具页点击小月饼兑换", Vector2(184, 176), Vector2(360, 56), 17, Color.WHITE, DARK_BLUE, 4, HORIZONTAL_ALIGNMENT_LEFT))
	page.add_child(_text("%d 个小月饼 = 1 个大月饼（五种口味随机，使用后持续一小时）" % int(moon.big_cost), Vector2(110, 244), Vector2(660, 28), 18, Color("ffd24a"), DARK_BLUE, 4, HORIZONTAL_ALIGNMENT_LEFT))
	var effects := ["生命上限 +600", "魔法上限 +600", "攻击力 +100", "防御力 +50", "装备掉落率 +50%"]
	for i: int in moon.big.size():
		var x: float = 112.0 + 142.0 * i
		page.add_child(_icon(moon.big[i], Vector2(x + 40, 276), 44))
		page.add_child(_text("%s\n%s" % [EquipmentCatalog.find(moon.big[i]).display_name, effects[i]], Vector2(x, 322), Vector2(124, 50), 15, Color.WHITE, DARK_BLUE, 4))
	page.add_child(_text("%d 个小月饼 = 1 把绝版武器（只会兑换本角色用的）" % int(moon.weapon_cost), Vector2(110, 384), Vector2(660, 28), 18, Color("ffd24a"), DARK_BLUE, 4, HORIZONTAL_ALIGNMENT_LEFT))
	for i in 3:
		var id: String = moon.weapons[["悟空", "唐僧", "八戒"][i]]
		var x := 150.0 + 200.0 * i
		page.add_child(_icon(id, Vector2(x, 416), 48))
		page.add_child(_text(EquipmentCatalog.find(id).display_name, Vector2(x + 54, 416), Vector2(110, 48), 20, Color.WHITE, DARK_BLUE, 5, HORIZONTAL_ALIGNMENT_LEFT))
	var sw := CheckButton.new()
	var caption := func(on: bool) -> String: return "中秋活动（BOSS 掉落小月饼）：%s" % ("开" if on else "关")
	sw.text = caption.call(GameState.moon_event)
	sw.button_pressed = GameState.moon_event
	sw.focus_mode = Control.FOCUS_NONE
	sw.position = Vector2(110, 482)
	sw.add_theme_font_size_override("font_size", 20)
	sw.toggled.connect(func(on: bool):
		GameState.moon_event = on
		sw.text = caption.call(on))
	page.add_child(sw)
	return page
