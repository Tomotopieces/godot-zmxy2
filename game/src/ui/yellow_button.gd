extends Button
## Generic yellow button (scenes/ui/components/yellow_button.tscn): gradient fill, 2 px black border, 5 px corners.
## Hover lightens the surface (the Light layer over the gradient); holding it down shows it plain.

@onready var _light: Control = $Fill/Light
var _down := false

func _ready() -> void:
	mouse_entered.connect(_update)
	mouse_exited.connect(_update)
	button_down.connect(func(): _down = true; _update())
	button_up.connect(func(): _down = false; _update())
	_update()

func _update() -> void:
	_light.visible = not disabled and not _down and is_hovered()
