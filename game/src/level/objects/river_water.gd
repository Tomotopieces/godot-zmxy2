@tool
class_name RiverWater
extends Node2D
## The water of 3-1 (the 忘川河 the boat sails on): a rectangle of `src/level/water.gdshader`, no pictures.
## A scene of its own (scenes/objects/river_water.tscn) placed in the stage scene (Objects/RiverWater) at the water line:
## the numbers are exports, pushed to the one child rect (`Surface`) and to its shader.

@export var size := Vector2(940.0, 200.0):        ## px, from the node's own y downwards
	set(v):
		size = v
		_sync()
@export var surface_color := Color(0.32, 0.6, 0.68, 1.0):
	set(v):
		surface_color = v
		_sync()
@export var deep_color := Color(0.02, 0.1, 0.16, 1.0):
	set(v):
		deep_color = v
		_sync()
@export var foam_color := Color(0.8, 0.94, 0.96, 1.0):
	set(v):
		foam_color = v
		_sync()
@export_range(0.0, 1.0, 0.01) var alpha := 0.9:
	set(v):
		alpha = v
		_sync()
@export var wave_height := 8.0:                    ## px the water line moves up and down
	set(v):
		wave_height = v
		_sync()
@export var wave_length := 180.0:                  ## px of the longest wave
	set(v):
		wave_length = v
		_sync()
@export var wave_speed := 0.8:                     ## waves per second
	set(v):
		wave_speed = v
		_sync()
@export var flow_speed := 30.0:                    ## px / s the streaks drift right
	set(v):
		flow_speed = v
		_sync()

func _ready() -> void:
	_sync()

## Hands the exports to the child rect and to its material.
func _sync() -> void:
	var s := get_node_or_null("Surface") as ColorRect
	if s == null:
		return
	s.size = size
	var m := s.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("surface_color", surface_color)
	m.set_shader_parameter("deep_color", deep_color)
	m.set_shader_parameter("foam_color", foam_color)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("wave_height", wave_height)
	m.set_shader_parameter("wave_length", wave_length)
	m.set_shader_parameter("wave_speed", wave_speed)
	m.set_shader_parameter("flow_speed", flow_speed)
