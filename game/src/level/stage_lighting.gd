class_name StageLighting
extends Node
## The look of a stage at night, from data/lighting/<stage>.json (a stage without a file is drawn as the original did):
##  - the scenery is dimmed (not the actors, pickups or numbers) and the far background a little less;
##  - bodies are lit from above by the moon and shaded below (Rig.set_light), and cast a long shadow away from it;
##  - drifting mist, in a patchy layer behind the actors and a thin one in front; it swells and thins on its own;
##  - the moon's glow and a few slow shafts of moonlight from it; wisps (鬼火) that fade in and out;
##  - a screen grade: cool shadows, a little less colour, a vignette.
## Draw order: far layer (-2), world, the effects layer (1), the grade layer (2), the HUD (3).

const FOG := preload("res://src/level/fog.gdshader")
const GRADE := preload("res://src/level/grade.gdshader")
const CAST := preload("res://src/level/cast_shadow.gdshader")

var _lv: Level
var _cfg: Dictionary
var _far_tint := Color.WHITE
var _fog_back: ColorRect
var _fog_back_mat: ShaderMaterial
var _fog_front: ColorRect
var _fog_front_mat: ShaderMaterial
var _moon: Node2D
var _shafts: Array[Polygon2D] = []
var _moon_glow: Sprite2D
var _shadows := {}      ## instance id of an actor -> {holder, rig, mat, sig, floor_y}
var _t := 0.0

## Starts the stage's lighting when it has a data file.
static func attach(lv: Level) -> StageLighting:
	var path := "res://data/lighting/%s.json" % lv.level_name
	if not ResourceLoader.exists(path):
		return null
	var s := StageLighting.new()
	s._cfg = JSON.parse_string(FileAccess.get_file_as_string(path))
	s._lv = lv
	s.process_physics_priority = 20   # after the level and the actors have moved
	lv.add_child(s)
	return s

static func _color(a: Array, alpha := 1.0) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]), alpha)

static var _glow_tex: GradientTexture2D

static func glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 256
		_glow_tex.height = 256
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
		_glow_tex.gradient = g
	return _glow_tex

func _ready() -> void:
	var scene: Dictionary = _cfg.scene
	for n in ["Art", "Ground"]:
		(_lv.world.get_node(n) as Node2D).modulate = _color(scene.art)
	_far_tint = _color(scene.far)
	_lv.far_sprite().modulate = _far_tint
	_build_fog()
	_build_effects()
	_build_grade()

func _build_fog() -> void:
	var f: Dictionary = _cfg.fog
	var holder := Node2D.new()
	holder.name = "Fog"
	holder.z_index = -5   # over the scenery and the floor, under every actor
	_lv.world.add_child(holder)
	_fog_back = ColorRect.new()
	_fog_back.size = Layers.VIEW
	_fog_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_back_mat = _fog_material(f, float(f.density), 0.0)
	_fog_back.material = _fog_back_mat
	holder.add_child(_fog_back)

func _fog_material(f: Dictionary, density: float, seed_: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOG
	m.set_shader_parameter("fog_color", _color(f.color))
	m.set_shader_parameter("density", density)
	m.set_shader_parameter("ground_bias", float(f.ground_bias))
	m.set_shader_parameter("speed", float(f.speed))
	m.set_shader_parameter("seed", seed_)
	return m

func _build_effects() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var f: Dictionary = _cfg.fog
	_fog_front = ColorRect.new()
	_fog_front.size = Layers.VIEW
	_fog_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_front_mat = _fog_material(f, float(f.front_density), 3.0)
	_fog_front_mat.set_shader_parameter("speed", float(f.speed) * 1.7)
	_fog_front.material = _fog_front_mat
	layer.add_child(_fog_front)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var m: Dictionary = _cfg.moon
	var mc := _color(m.glow)
	_moon = Node2D.new()
	layer.add_child(_moon)
	_moon_glow = Sprite2D.new()
	_moon_glow.texture = glow_texture()
	_moon_glow.scale = Vector2(2.6, 2.6)
	_moon_glow.modulate = Color(mc, 0.30)
	_moon_glow.material = add
	_moon.add_child(_moon_glow)
	# slow shafts of moonlight fanning out from the moon to the lower right
	for i in int(m.shafts):
		var p := Polygon2D.new()
		var w0 := 14.0 + 10.0 * i
		var w1 := 70.0 + 42.0 * i
		var len := 760.0 + 90.0 * i
		p.polygon = PackedVector2Array([Vector2(-w0, 0), Vector2(w0, 0), Vector2(w1, len), Vector2(-w1, len)])
		p.texture = _soft_edge()   # bright in the middle, fading to both sides: no hard beam edges
		p.uv = PackedVector2Array([Vector2(0, 0), Vector2(64, 0), Vector2(64, 4), Vector2(0, 4)])
		var a := float(m.shaft_alpha) * (1.0 - 0.18 * i)
		p.vertex_colors = PackedColorArray([Color(mc, a), Color(mc, a), Color(mc, 0.0), Color(mc, 0.0)])
		p.rotation = deg_to_rad(-(float(m.angle) - 13.0 + 13.0 * i))
		p.material = add
		_moon.add_child(p)
		_shafts.append(p)
	_build_wisps(layer, add)

static var _edge_tex: GradientTexture2D

static func _soft_edge() -> GradientTexture2D:
	if _edge_tex == null:
		_edge_tex = GradientTexture2D.new()
		_edge_tex.fill = GradientTexture2D.FILL_LINEAR
		_edge_tex.fill_from = Vector2(0.0, 0.0)
		_edge_tex.fill_to = Vector2(1.0, 0.0)
		_edge_tex.width = 64
		_edge_tex.height = 4
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_edge_tex.gradient = g
	return _edge_tex

func _build_wisps(layer: CanvasLayer, add: CanvasItemMaterial) -> void:
	var w: Dictionary = _cfg.wisps
	var c := _color(w.color)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(c, 0.0), Color(c, 0.55), Color(c, 0.4), Color(c, 0.0)])
	var p := CPUParticles2D.new()
	p.amount = int(w.count)
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(480, 130)
	p.position = Vector2(470, 400)
	p.direction = Vector2(1, -0.3)
	p.spread = 70.0
	p.gravity = Vector2(0, -3)
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 16.0
	p.tangential_accel_min = -5.0
	p.tangential_accel_max = 5.0
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.2
	p.texture = glow_texture()
	p.color_ramp = ramp
	p.material = add
	layer.add_child(p)

func _build_grade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var r := ColorRect.new()
	r.size = Layers.VIEW
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = GRADE
	var g: Dictionary = _cfg.grade
	m.set_shader_parameter("vignette", float(g.vignette))
	m.set_shader_parameter("saturation", float(g.saturation))
	r.material = m
	layer.add_child(r)

func _physics_process(delta: float) -> void:
	_t += delta
	var vr := _lv.view_rect()
	_fog_back.global_position = vr.position
	_fog_back_mat.set_shader_parameter("scroll", Vector2(vr.position.x * 0.85, 0.0))
	_fog_front_mat.set_shader_parameter("scroll", Vector2(vr.position.x * 1.25, 0.0))
	var far := _lv.far_sprite()
	_moon.position = far.position + Vector2(float(_cfg.moon.x), float(_cfg.moon.y))
	for i in _shafts.size():
		_shafts[i].modulate.a = 0.55 + 0.45 * sin(_t * (0.35 + 0.11 * i) + 1.7 * i)
	_moon_glow.modulate.a = 0.26 + 0.05 * sin(_t * 0.6)
	var actors: Array = [_lv.hero] + _lv.monsters()
	var seen := {}
	for a in actors:
		if not is_instance_valid(a) or a.rig == null:
			continue
		seen[a.get_instance_id()] = true
		_update_actor(a)
	for id in _shadows.keys():
		if not seen.has(id):
			(_shadows[id].holder as Node2D).queue_free()
			_shadows.erase(id)

func _update_actor(a: Actor) -> void:
	var rig: Rig = a.rig
	var id := a.get_instance_id()
	var b: Dictionary = _cfg.body
	if not _shadows.has(id):
		rig.set_light(_color(b.shade), _color(b.lit), float(b.height))
		_shadows[id] = _make_shadow(a)
	# an actor's origin is not at its feet: the feet are the bottom of its body shape
	var feet_off := a.body_shape.position.y + (a.body_shape.shape as RectangleShape2D).size.y / 2.0
	var feet_y := a.global_position.y + feet_off
	rig.set_feet(feet_y)
	var e: Dictionary = _shadows[id]
	var sh: Dictionary = _cfg.shadow
	if a.is_on_floor():
		e.floor_y = feet_y
	var holder: Node2D = e.holder
	var srig: Rig = e.rig
	var shown := a.is_visible_in_tree() and rig.is_visible_in_tree()
	holder.visible = shown
	if not shown:
		return
	var floor_y: float = e.floor_y
	holder.global_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-float(sh.shear), -float(sh.squash)), Vector2(a.global_position.x, floor_y)).translated_local(Vector2(0.0, -feet_off))
	srig.mirror(rig)
	var sig := "%s|%s" % [rig.action, rig.equipment]
	if e.sig != sig:
		e.sig = sig
		for sp: Sprite2D in srig.find_children("*", "Sprite2D", true, false):
			sp.material = e.mat
	var high := clampf(1.0 - (floor_y - feet_y) / 280.0, 0.25, 1.0)
	(e.mat as ShaderMaterial).set_shader_parameter("shadow_color", Color(0.02, 0.03, 0.08, float(sh.alpha) * high))

func _make_shadow(a: Actor) -> Dictionary:
	var holder := Node2D.new()
	holder.z_index = -2   # over the floor, under every actor
	holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_lv.world.add_child(holder)
	var srig := Rig.create(a.get("data").rig)
	holder.add_child(srig)
	var mat := ShaderMaterial.new()
	mat.shader = CAST
	return {"holder": holder, "rig": srig, "mat": mat, "sig": "", "floor_y": float(_cfg.shadow.floor_y)}
