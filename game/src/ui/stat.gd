@tool
extends Control
## One backpack attribute row: caption + value box. Edit `caption` / `width` per instance in the inspector.

@export var caption: String = "装备":
	set(value):
		caption = value
		_apply()

@export var width: int = 108:   ## value box width (px)
	set(value):
		width = value
		_apply()


func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_node_ready():
		return   # _ready() applies the rest once the children are ready
	$Caption.text = caption
	$Box.size.x = width
## The value shown in the box.
func set_value(t: String) -> void:
	$Box/StatValue.text = t
