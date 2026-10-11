class_name ActivityPanel
extends CanvasLayer
## 活动 (SelectPLace.huodongbtn -> export.huodong.ChineseValentinesDay): the past events of the original, each a one-a-day
## trip into its own stage. The panel is the original 七夕 one (picture, GO, close); the 国庆 page's own picture is not
## kept in the files, so it is laid out in the same frame.
##   七夕: 9-1 宋帝王, +10 功勋 on entering; the 喜鹊 / 水牛 it frees drop 幸运的喜鹊 / 顽固的水牛.
##   国庆: 11-1 劈天斧 / 风神盾 (one of the two); killing 劈天斧 gives 攻击 +100, 风神盾 防御 +50, for an hour.
## (中秋 needs no entry: every boss drops 小月饼, which the bag exchanges.)

signal play(stage: Vector2i)

const PAGES := [
	{"id": "qixi", "stage": Vector2i(9, 1), "reward": 10},
	{"id": "guoqing", "stage": Vector2i(11, 1), "reward": 0},
]
const FRAME := Rect2(85, 32, 773, 520)   ## the picture's frame, in layout space
const DONE_TEXT := "您已经参加过活动了，请明天再来吧"

var _ui: UiLayout
var _art: Node
var _page2: Control
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
	_art = _ui.get_child(0)   # the picture; GO and close are drawn over it
	_page2 = _build_guoqing()
	_ui.add_child(_page2)
	_ui.move_child(_page2, 1)
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
	_page2.visible = _page == 1
	_label.text = "%d / %d" % [_page + 1, PAGES.size()]

func _on_button(b: String) -> void:
	if b == "btn_x":
		queue_free()
		return
	if b != "btn_go":
		return
	var p: Dictionary = PAGES[_page]
	if GameState.activity_done(p.id):
		Toast.show_on(self, DONE_TEXT)
		return
	GameState.mark_activity(p.id)
	if int(p.reward) > 0:
		GameState.merit += int(p.reward)
		GameState.notice = "七夕快乐，获得 功勋+%d" % int(p.reward)
	play.emit(p.stage)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()
	elif e.is_action_pressed("move_left"):
		_turn(-1)
	elif e.is_action_pressed("move_right"):
		_turn(1)

# ------------------------------------------------------------------ the 国庆 page

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

func _text(text: String, pos: Vector2, size: Vector2, font: int, color: Color, outline: Color, outline_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size = size
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", outline_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_guoqing() -> Control:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_box(FRAME, Color("4a63c8"), Color("1c2260"), 22, 3))
	var inner := Rect2(FRAME.position + Vector2(22, 22), FRAME.size - Vector2(44, 44))
	page.add_child(_box(inner, Color("2a1f55"), Color("1c2260"), 16, 2))
	page.add_child(_text("国庆献礼", Vector2(420, 60), Vector2(420, 70), 56, Color("ffe27a"), Color("5a2a9a"), 10))
	page.add_child(_text("决战劈天斧 · 风神盾", Vector2(380, 132), Vector2(460, 56), 36, Color("f1e4ff"), Color("5a2a9a"), 8))
	var tip := _box(Rect2(136, 430, 548, 86), Color("c8321c"), Color("fff0b0"), 12, 2)
	page.add_child(tip)
	page.add_child(_text("每天只能进入一次国庆副本。击败劈天斧，攻击 +100；击败风神盾，防御 +50，各持续一小时。",
		Vector2(150, 436), Vector2(520, 74), 20, Color.WHITE, Color("5a1208"), 3))
	var tag := _box(Rect2(150, 408, 96, 30), Color("4a8a1c"), Color("fff0b0"), 8, 2)
	page.add_child(tag)
	page.add_child(_text("温馨提示", Vector2(150, 408), Vector2(96, 30), 18, Color("ffd24a"), Color("2a4a0c"), 3))
	for e in [["monster79", Vector2(260, 330), 1.5], ["monster80", Vector2(560, 300), 1.4]]:
		var rig := Rig.create(e[0])
		rig.position = e[1]
		rig.scale = Vector2.ONE * float(e[2])
		page.add_child(rig)
		rig.ready.connect(rig.play.bind(&"wait"))
	return page
