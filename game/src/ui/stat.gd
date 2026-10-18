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
	# the value label's piece name is set as soon as the label exists: UiLayout.create() collects the pieces right after
	# instancing, before any _ready()
	var v := get_node_or_null(^"Box/StatValue")
	if v and piece != "":
		v.set_meta(&"ui_piece", [piece])
	if not is_node_ready():
		return   # _ready() applies the rest once the children are ready
	$Caption.text = caption
	$Box.size.x = width
