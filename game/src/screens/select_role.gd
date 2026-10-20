class_name SelectRole
extends CanvasLayer
## Hero choice for a new game (export.SelectRole): 孙悟空 / 唐僧 / 猪八戒. 猪八戒 stays locked until the first 红孩儿 kill.

signal chosen(role: String)
signal cancelled

const BUTTONS := {"btn1": "wukong", "btn2": "tangseng", "btn3": "bajie"}

var _ui: UiLayout

func _ready() -> void:
	_ui = UiLayout.create("select_role")
	add_child(_ui)
	_ui.set_visible_piece("lockmc", false)
	_ui.button_pressed.connect(_on_button)
	var lock := _ui.get_piece("btn3") as CanvasItem
	if not GameState.unlocked.get("bajie", false):
		lock.modulate = Color(0.3, 0.3, 0.3)
		var l := Label.new()
		l.text = "击败红孩儿后解锁"
		l.add_theme_font_override("font", preload("res://assets/fonts/LXGW975YuanSC-500W.ttf"))
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(467, 330)   # centred on the third portrait
		l.size = Vector2(234, 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	Snd.music("begin")

func _on_button(b: String) -> void:
	var role: String = BUTTONS.get(b, "")
	if role != "" and GameState.unlocked.get(role, false):
		chosen.emit(role)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
