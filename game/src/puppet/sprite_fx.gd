class_name SpriteFx
extends RefCounted
## Builds the per-sprite effect materials (src/puppet/sprite_fx.gdshader): halo, tint matrix, blur.

const SHADER := preload("res://src/puppet/sprite_fx.gdshader")
const SHADER_ADD := preload("res://src/puppet/sprite_fx_add.gdshader")

## A glow that can be driven at run time (UI pulses, character halos).
static func glow_material(color: Color, reach: float, strength: float, solid := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("glow_on", true)
	m.set_shader_parameter("solid", solid)
	set_glow(m, color, reach, strength)
	return m

static func set_glow(m: ShaderMaterial, color: Color, reach: float, strength: float) -> void:
	m.set_shader_parameter("glow_color", color)
	m.set_shader_parameter("glow_blur", reach)
	m.set_shader_parameter("glow_strength", strength)
	m.set_shader_parameter("extend", reach + 1.0)
