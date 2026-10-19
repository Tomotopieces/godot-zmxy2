extends Button
## Generic yellow button (scenes/ui/components/yellow_button.tscn): gradient fill, 2 px black border, 5 px corners.
## Hover (or pad focus) shows a 5 px white glow around the edge; holding it down hides the glow.

@onready var _glow: Control = $Glow
var _down := false

func _ready() -> void:
	mouse_entered.connect(_update)
	mouse_exited.connect(_update)
	focus_entered.connect(_update)
	focus_exited.connect(_update)
	button_down.connect(func(): _down = true; _update())
	button_up.connect(func(): _down = false; _update())
	_update()

func _update() -> void:
	_glow.visible = not disabled and not _down and (is_hovered() or has_focus())
