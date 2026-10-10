class_name SpriteFx
extends RefCounted
## Builds the per-sprite effect materials (src/rig/sprite_fx.gdshader): halo, tint matrix, blur.

const SHADER := preload("res://src/rig/sprite_fx.gdshader")
const SHADER_ADD := preload("res://src/rig/sprite_fx_add.gdshader")

## From a chain of effects as authored in the original ([{t: "glow"|"blur"|"matrix", ...}]). Null when it does nothing.
static func material_for(chain: Array, additive := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_ADD if additive else SHADER
	var extend := 0.0
	var used := false
	var glows := 0
	var reach1 := 0.0
	for f in chain:
		match f.t:
			"blur":
				var b := maxf(float(f.x), float(f.y))
				if b > 0.0:
					m.set_shader_parameter("blur", b)
					extend = maxf(extend, b)
					used = true
			"glow":
				if float(f.s) > 0.0 and f.has("c"):
					var b := maxf(float(f.x), float(f.y))
					var col := Color(f.c[0] / 255.0, f.c[1] / 255.0, f.c[2] / 255.0, f.c[3] / 255.0)
					glows += 1
					if glows == 1:
						m.set_shader_parameter("glow_on", true)
						m.set_shader_parameter("glow_blur", b)
						m.set_shader_parameter("glow_strength", float(f.s))
						m.set_shader_parameter("glow_color", col)
						reach1 = b
						extend = maxf(extend, b)
					else:
						# the next glow of a chain wraps the first one's halo: it reaches that much further
						m.set_shader_parameter("glow2_on", true)
						m.set_shader_parameter("glow2_blur", reach1 + b)
						m.set_shader_parameter("glow2_strength", float(f.s) * 2.5)   # (its reach is wider, so the average under the halo edge is lower)
						m.set_shader_parameter("glow2_color", col)
						extend = maxf(extend, reach1 + b)
					used = true
			"matrix":
				var a: Array = f.m
				m.set_shader_parameter("matrix_on", true)
				m.set_shader_parameter("color_matrix", Projection(
					Vector4(a[0], a[5], a[10], a[15]), Vector4(a[1], a[6], a[11], a[16]),
					Vector4(a[2], a[7], a[12], a[17]), Vector4(a[3], a[8], a[13], a[18])))
				m.set_shader_parameter("color_offset", Vector4(a[4], a[9], a[14], a[19]) / 255.0)
				used = true
	if not used:
		return null
	m.set_shader_parameter("extend", extend + 1.0 if extend > 0.0 else 0.0)
	return m

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
