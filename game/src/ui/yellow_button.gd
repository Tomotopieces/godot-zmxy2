extends Button
## Generic yellow button (scenes/ui/components/yellow_button.tscn): gradient fill, 2 px black border, 5 px corners.
## Hover lightens the surface (the Light layer over the gradient); holding it down shows it plain; disabled turns the
## fill gray.

const YELLOW := preload("res://assets/textures/yellow_gradient.tres")
const GRAY := preload("res://assets/textures/gray_gradient.tres")

@onready var _light: Control = $Fill/Light
@onready var _fill: TextureRect = $Fill/Gradient
var _down := false

func _ready() -> void:
	for s in [mouse_entered, mouse_exited, focus_entered, focus_exited]:   # (the pad's focus lights it like a hover)
		s.connect(_update)
	button_down.connect(func(): _down = true; _update())
	button_up.connect(func(): _down = false; _update())
	draw.connect(_update)   # a Button redraws when `disabled` changes
	_update()

func _update() -> void:
	_fill.texture = GRAY if disabled else YELLOW
	_light.visible = not disabled and not _down and (is_hovered() or has_focus())
