class_name StageLighting
extends Node
## The look of a stage at night, from data/lighting/<stage>.json (a stage without a file is drawn as the original did):
##  - the scenery and the floor are dimmed (not the actors, pickups or numbers) and the far background a little less; the
##    decoration gets a rim of backlight on the edges facing the moon and fades to dark towards the floor;
##  - bodies are lit from above by the moon, shaded below and rimmed on their upper-left edges (Rig.set_light), and cast a
##    soft shadow away from it;
##  - drifting mist, in a patchy layer behind the actors and a thin one in front; it swells and thins on its own;
##  - the moon's glow and a few slow shafts of moonlight from it - in the sky only: behind all scenery and actors;
##  - a screen grade: cool shadows, a little less colour, a vignette.
## Draw order: far layer (-2), the moonlight layer (-1), world, the mist layer (1), the grade layer (2), the HUD (3).

const FOG := preload("res://src/level/fog.gdshader")
const GRADE := preload("res://src/level/grade.gdshader")
const CAST := preload("res://src/level/cast_shadow.gdshader")
const ART := preload("res://src/level/art_look.gdshader")

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
var _treasure_rig: Rig

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
	(_lv.world.get_node("Art") as Node2D).modulate = _color(scene.art)
	(_lv.world.get_node("Ground") as Node2D).modulate = _color(scene.ground)
	_far_tint = _color(scene.far)
	_lv.far_sprite().modulate = _far_tint
	_light_scenery(scene)
	_build_fog()
	_build_effects()
	_build_grade()

## The art's own material: backlight rim; the decoration (not the floor) also fades to dark at its feet.
func _light_scenery(scene: Dictionary) -> void:
	# one material per layer: the children of "Art" (the depth layers of a hand-made scene, scenes/levels/<stage>.tscn: "Far",
	# "Near", ...) each get the settings of their name under "layers" of the lighting file; the floor has its own
	var layers: Dictionary = _cfg.get("layers", {})
	var groups := {"Ground": [_lv.world.get_node("Ground"), {"fade": 0.0}]}
	groups["Art"] = [_lv.world.get_node("Art"), {}]
	for n in (_lv.world.get_node("Art") as Node2D).get_children():
		if n is Node2D and not n is Sprite2D:
			groups[n.name] = [n, layers.get(String(n.name), {})]
	for name_ in groups:
		var node: Node2D = groups[name_][0]
		var o: Dictionary = groups[name_][1]
		var m := ShaderMaterial.new()
		m.shader = ART
		m.set_shader_parameter("rim_color", _color(scene.rim_color))
		m.set_shader_parameter("rim_strength", float(o.get("rim", float(scene.rim_strength))))
		m.set_shader_parameter("rim_width", float(scene.rim_width))
		m.set_shader_parameter("ground_y", float(scene.ground_y))
		m.set_shader_parameter("fade_height", 0.0 if name_ == "Ground" else float(scene.fade_height) * float(o.get("fade", 1.0)))
		m.set_shader_parameter("fade_dark", float(scene.fade_dark))
		m.set_shader_parameter("blur", float(o.get("blur", 0.0)))
		if o.has("tint"):
			node.modulate = _color(o.tint)
		var sprites: Array = node.find_children("*", "Sprite2D", true, false) if name_ != "Art" else node.get_children().filter(func(c): return c is Sprite2D)
		for sp: Sprite2D in sprites:
			if sp.material == null:
				sp.material = m

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
	m.set_shader_parameter("max_alpha", float(f.max_alpha))
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
	var sky := CanvasLayer.new()   # behind the world: scenery and actors stand in front of the moonlight
	sky.layer = -1
	add_child(sky)
	_moon = Node2D.new()
	sky.add_child(_moon)
	_moon_glow = Sprite2D.new()
	_moon_glow.texture = glow_texture()
	_moon_glow.scale = Vector2(2.6, 2.6)
	_moon_glow.modulate = Color(mc, 0.30)
	_moon_glow.material = add
	_moon.add_child(_moon_glow)
	# slow shafts of moonlight fanning out from the moon to the lower right
	for i in int(m.shafts):
		var p := Polygon2D.new()
		var w0 := 10.0 + 8.0 * i
		var w1 := 70.0 + 42.0 * i
		var len := 760.0 + 90.0 * i
		var lm := len * 0.16                 # where the beam is at its brightest: it grows out of the moon's glow
		var wm := lerpf(w0, w1, 0.16)
		p.polygon = PackedVector2Array([Vector2(-w0, 0), Vector2(w0, 0), Vector2(wm, lm), Vector2(w1, len), Vector2(-w1, len), Vector2(-wm, lm)])
		p.texture = _soft_edge()   # bright in the middle, fading to both sides: no hard beam edges
		p.uv = PackedVector2Array([Vector2(0, 0), Vector2(64, 0), Vector2(64, 4), Vector2(64, 4), Vector2(0, 4), Vector2(0, 4)])
		var a := float(m.shaft_alpha) * (1.0 - 0.18 * i)
		p.vertex_colors = PackedColorArray([Color(mc, 0.0), Color(mc, 0.0), Color(mc, a), Color(mc, 0.0), Color(mc, 0.0), Color(mc, a)])
		p.rotation = deg_to_rad(-(float(m.angle) - 13.0 + 13.0 * i))
		p.material = add
		_moon.add_child(p)
		_shafts.append(p)

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
	var tr: Treasure = _lv.hero.treasure
	if is_instance_valid(tr) and tr.rig != null and tr.rig != _treasure_rig:
		_treasure_rig = tr.rig   # the hero's magic treasure: a mild even tint and the backlight rim (it floats, so no gradient)
		var b: Dictionary = _cfg.body
		var mid := _color(b.shade).lerp(_color(b.lit), 0.5)
		_treasure_rig.set_light(mid, mid, float(b.height), float(b.rim_strength), float(b.rim_width))
	for id in _shadows.keys():
		if not seen.has(id):
			(_shadows[id].holder as Node2D).queue_free()
			_shadows.erase(id)

func _update_actor(a: Actor) -> void:
	var rig: Rig = a.rig
	var id := a.get_instance_id()
	var b: Dictionary = _cfg.body
	if not _shadows.has(id):
		rig.set_light(_color(b.shade), _color(b.lit), float(b.height), float(b.rim_strength), float(b.rim_width))
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
	(e.mat as ShaderMaterial).set_shader_parameter("blur", float(sh.blur))

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
