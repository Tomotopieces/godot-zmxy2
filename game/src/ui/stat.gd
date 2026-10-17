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

@export var piece: String = "":   ## the `ui_piece` the layout reaches the value label by (e.g. txt_hp); "" = none
	set(value):
		piece = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_node_ready():
		return   # _ready() applies the values once the children exist
	$Caption.text = caption
	$Box.size.x = width
	if piece != "":
		$Box/StatValue.set_meta(&"ui_piece", [piece])
