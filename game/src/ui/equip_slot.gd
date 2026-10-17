@tool
extends Control
## One backpack attribute row: caption + value box. Edit `caption` / `width` per instance in the inspector.

@export var caption: String = "装备":
	set(value):
		caption = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_node_ready():
		return   # _ready() applies the values once the children exist
	$Caption.text = caption
