@tool
extends Button
## Text button drawn as gradient-filled text with a black outline (scenes/ui/components/gradient_button.tscn).
## The Button's own text stays invisible: `caption` is shown by the Outline label (black, outlined) and the Fill
## label, whose shape clips the Gradient texture. Hover lightens it.

@export var caption := "按钮":
	set(v):
		caption = v
		if is_node_ready():
			$Outline.text = v
			$Fill.text = v

func _ready() -> void:
	$Outline.text = caption
	$Fill.text = caption
	if Engine.is_editor_hint():
		return
	for lit in [mouse_entered, focus_entered]:   # (the pad's focus too)
		lit.connect(func(): modulate = Color(1.3, 1.3, 1.3))
	for out in [mouse_exited, focus_exited]:
		out.connect(func(): modulate = Color.WHITE)
