class_name Toast
extends Label
## Notice text (export.Infomation, Config.ts): 32 px black text with a white glow, centred across the screen.
## The remake shortens the original's glide (270 -> 170, 240 for saves) for every notice alike: it starts at y 230,
## glides up 15 px in 1.5 s, stays 0.5 s and fades out in 0.5 s. One notice per screen: a new one replaces the current one.

const FONT_SIZE := 22
const START_Y := 230.0
const END_Y := 215.0
const RISE := 1.5
const HOLD := 0.5
const FADE := 0.5

var _tw: Tween

static func show_on(parent: Node, text: String, end_y := -1.0) -> void:
	if text == "":
		return
	var t: Toast = parent.get_node_or_null("Toast")
	if t == null:
		t = Toast.new()
		t.name = "Toast"
		parent.add_child(t)
	t._show(text, end_y if end_y >= 0.0 else END_Y)

func _init() -> void:
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", Color.BLACK)
	add_theme_color_override("font_outline_color", Color.WHITE)
	add_theme_constant_override("outline_size", 5)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size = Vector2(Level.VIEW.x, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	process_mode = Node.PROCESS_MODE_ALWAYS   # notices also show over paused screens

func _show(t: String, end_y: float) -> void:
	text = t
	move_to_front()
	modulate.a = 1.0
	position = Vector2(0, START_Y)
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "position:y", end_y, RISE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_interval(HOLD)
	_tw.tween_property(self, "modulate:a", 0.0, FADE)
	_tw.tween_callback(queue_free)
