@tool
class_name EquipSlot
extends Node2D
## A rig part whose look depends on the equipped item.
## `variants` maps equipment show-id -> PackedScene (static sprites, or a looping AnimationPlayer for wings).
## cloth_ex slots show variant (cloth id) and are empty for ids without an entry.

@export_enum("cloth", "cloth_ex", "weapon", "wing") var kind := "cloth"
@export var variants: Dictionary = {}
@export var variant_id := 1:
	set(v):
		variant_id = v
		if is_inside_tree():
			_apply()

var _inst: Node

func _ready() -> void:
	_apply()

func set_variant(id: int) -> void:
	variant_id = id

func _apply() -> void:
	if _inst:
		_inst.queue_free()
		_inst = null
	var ps: PackedScene = variants.get(variant_id)
	if ps:
		_inst = ps.instantiate()
		add_child(_inst)
		if material != null:   # an effect on the slot (halo, tint) applies to its sprites
			for c: CanvasItem in _inst.find_children("*", "CanvasItem", true, false) + [_inst]:
				c.use_parent_material = true   # every level down to the sprites takes the slot's effect
