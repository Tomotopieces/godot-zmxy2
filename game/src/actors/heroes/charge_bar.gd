class_name ChargeBar
extends Node2D
## 唐僧's hold-to-charge meter above his head (my/ExceedPower): red frame, green fill, flashing when full.

const SIZE := Vector2(45, 9)

var value := 0.0   ## 0..1
var _flash := false

func _ready() -> void:
	visible = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	visible = value > 0.0
	_flash = not _flash
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color.RED, false, 1.0)
	var fill := Color("#aabbcc") if value >= 1.0 and _flash else (Color("#112233") if value >= 1.0 else Color("#00ff00"))
	draw_rect(Rect2(Vector2(1, 1), Vector2((SIZE.x - 2) * value, SIZE.y - 2)), fill)
