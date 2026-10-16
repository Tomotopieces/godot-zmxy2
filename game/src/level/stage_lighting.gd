class_name StageLighting
extends Node
## The look of a stage at night, from data/lighting/<stage>.json (a stage without a file is drawn as the original did):
##  - the scenery and the floor are dimmed (not the actors, pickups or numbers) and the far background a little less; the
##    decoration gets a rim of backlight on the edges facing the moon and fades to dark towards the floor;
##  - bodies are lit from above by the moon, shaded below and rimmed on their upper-left edges (Rig.set_light), and cast a
##    soft shadow away from it;
##  - drifting mist, in a patchy layer behind the actors and a thin one in front; it swells and thins on its own;
##  - the moon's glow and a few slow shafts of moonlight from it - in the sky only: behind all scenery and actors
##    (a stage without "moon" in its file has none);
##  - rain ("rain": streaks that splash where they land on the floor) and, for a storm, lightning ("lightning": the screen
##    flashes and a bolt shows in the sky behind the scenery);
##  - a screen grade: cool shadows, a little less colour, a vignette, optionally darker ("brightness").
##  - the lamps of a hall ("lamps": a soft additive glow each, wavering) and ash drifting down through the frame ("ash",
##    a spray of small squares over everything);
##  - a stage may take another stage's look as its base ("use": that stage's name): every other entry of its own file is
##    copied over it (shallow), so only what differs from that look has to be written.
## Draw order: far layer (-2), the moonlight layer (-1), world, the mist layer (1), the grade layer (2), the HUD (3).

const FOG := preload("res://src/level/fog.gdshader")
const GRADE := preload("res://src/level/grade.gdshader")
const CAST := preload("res://src/level/cast_shadow.gdshader")
const ART := preload("res://src/level/art_look.gdshader")
const RAIN := preload("res://src/level/rain.gdshader")

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
var _lamps: Array[Sprite2D] = []   ## the hall's lamps: additive glows that waver (one per "lamps" entry)
var _t := 0.0
var _treasure_rig: Rig
var _sky: CanvasLayer           ## behind the world: the moon's light and the lightning bolt
var _flash: ColorRect
var _rain_mat: ShaderMaterial
var _flash_mat: ShaderMaterial
var _bolt: Node2D
var _strike_at := 0.0           ## time of the next lightning
var _strike_t := -1.0           ## seconds since the current one began (-1 = none)
var _dice := RandomNumberGenerator.new()   ## the weather has its own dice: gameplay's Rng stays untouched

## Starts the stage's lighting when it has a data file.
static func attach(lv: Level) -> StageLighting:
	var path := "res://data/lighting/%s.json" % lv.level_name
	if not ResourceLoader.exists(path):
		return null
	var s := StageLighting.new()
	s._cfg = JSON.parse_string(FileAccess.get_file_as_string(path))
	var use: String = s._cfg.get("use", "")
	if use != "":   # this stage is the other one's look with a few entries replaced
		var base_path := "res://data/lighting/%s.json" % use
		var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base_path)) if ResourceLoader.exists(base_path) else {}
		for k in s._cfg:
			if k != "use":
				base[k] = s._cfg[k]
		s._cfg = base
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
	_build_lamps()
	_build_rain()
	_build_ash()
	_build_lightning()
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
	var mats := {}
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
		# the pictures: Sprite2D, and the TextureRects that tile a floor or a haze band
		var pics: Array = node.find_children("*", "CanvasItem", true, false) if name_ != "Art" else node.get_children()
		for pic: CanvasItem in pics:
			if (pic is Sprite2D or pic is TextureRect) and pic.material == null:
				pic.material = m
		mats[name_] = m
	# mechanisms that stand in the world (Objects) but are drawn like scenery (group "lit_scenery": 刑天门 ...): the
	# scenery's dimming and the material of the "Near" layer (or of Art when the scene has no Near)
	var near: ShaderMaterial = mats.get("Near", mats["Art"])
	for n in get_tree().get_nodes_in_group(&"lit_scenery"):
		if (_lv.world.get_node("Art") as Node).is_ancestor_of(n):
			continue   # already lit as a piece of its layer
		(n as CanvasItem).modulate = _color(scene.art)
		for pic in n.find_children("*", "Sprite2D", true, false):
			if pic.material == null:
				pic.material = near

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
	_sky = CanvasLayer.new()   # behind the world: scenery and actors stand in front of the moonlight
	_sky.layer = -1
	add_child(_sky)
	if not _cfg.has("moon"):
		return
	var m: Dictionary = _cfg.moon
	var mc := _color(m.glow)
	_moon = Node2D.new()
	_sky.add_child(_moon)
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

## Rain over the actors (shader rain.gdshader): thin streaks and splashes on the floor. Every number is in the "rain" entry.
func _build_rain() -> void:
	if not _cfg.has("rain"):
		return
	var r: Dictionary = _cfg.rain
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.size = Layers.VIEW
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = RAIN
	m.set_shader_parameter("rain_color", _color(r.color))
	for k in ["amount", "speed", "length_px", "slant", "alpha", "splash_alpha", "land_y", "density", "splash_size"]:
		if r.has(k):
			m.set_shader_parameter(k, float(r[k]))
	rect.material = m
	_rain_mat = m
	layer.add_child(rect)

## The hall's lamps: an additive radial glow each, sized by its radius and wavering on its own. Numbers in the "lamps" entries.
func _build_lamps() -> void:
	if not _cfg.has("lamps"):
		return
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for l: Dictionary in _cfg.lamps:
		var s := Sprite2D.new()
		s.texture = glow_texture()   # 256 px: the glow reaches its radius at half of that
		s.scale = Vector2.ONE * (float(l.radius) / (glow_texture().width / 2.0))
		s.modulate = Color(_color(l.color), float(l.alpha))
		s.material = add
		s.z_index = -6   # over the scenery (-10) and the floor (-7), under every actor
		s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		s.position = Vector2(float(l.x), float(l.y))
		_lv.world.add_child(s)
		_lamps.append(s)

static var _ash_tex: ImageTexture

static func ash_texture() -> ImageTexture:
	if _ash_tex == null:   # a 4x4 white square: a flake's own size is its scale (px = 4 * scale)
		var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_ash_tex = ImageTexture.create_from_image(img)
	return _ash_tex

## Ash drifting down through the frame (a screen-space CPUParticles2D): a slow sideways sway, a small square each.
## Every number is in the "ash" entry.
func _build_ash() -> void:
	if not _cfg.has("ash"):
		return
	var a: Dictionary = _cfg.ash
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var p := CPUParticles2D.new()
	p.emitting = true
	p.amount = int(a.amount)
	p.lifetime = float(a.lifetime)
	p.preprocess = float(a.lifetime)   # the air is already full of ash when the stage opens
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(Layers.VIEW.x * 0.6, 10.0)
	p.position = Vector2(Layers.VIEW.x * 0.5, -20.0)   # above the top of the frame, so the flakes drift into it
	p.direction = Vector2(0.0, 1.0)
	p.spread = 25.0
	p.gravity = Vector2.ZERO   # they fall at their own slow pace, not the world's
	p.initial_velocity_min = float(a.speed[0])
	p.initial_velocity_max = float(a.speed[1])
	p.scale_amount_min = float(a.size[0]) / 4.0
	p.scale_amount_max = float(a.size[1]) / 4.0
	p.texture = ash_texture()
	p.color = Color(_color(a.color), float(a.alpha))
	var g := Gradient.new()   # fading in over the first tenth of a flake's fall, out over its last quarter
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = g
	p.orbit_velocity_min = 0.0
	p.orbit_velocity_max = 0.0
	p.angular_velocity_min = 0.0
	p.angular_velocity_max = 0.0
	p.tangential_accel_min = -float(a.sway)   # a slow sway to the sides as it falls
	p.tangential_accel_max = float(a.sway)
	layer.add_child(p)

## Lightning: now and then the screen flashes (a quick double or triple flicker) and a bolt shows in the sky.
func _build_lightning() -> void:
	if not _cfg.has("lightning"):
		return
	var l: Dictionary = _cfg.lightning
	_dice.randomize()
	_strike_at = _dice.randf_range(float(l.interval[0]) * 0.4, float(l.interval[1]) * 0.6)   # the first one comes early
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_flash = ColorRect.new()
	_flash.size = Layers.VIEW
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(_color(l.color), 0.0)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = add
	layer.add_child(_flash)
	_bolt = Node2D.new()
	_bolt.modulate.a = 0.0
	_bolt.material = add
	_sky.add_child(_bolt)

func _new_bolt() -> void:
	for c in _bolt.get_children():
		c.queue_free()
	var x := _dice.randf_range(120.0, Layers.VIEW.x - 120.0)
	var pts := PackedVector2Array([Vector2(x, -10.0)])
	var y := -10.0
	var bottom := _dice.randf_range(280.0, 400.0)
	var branch_from := Vector2.ZERO
	while y < bottom:
		y += _dice.randf_range(28.0, 52.0)
		x += _dice.randf_range(-34.0, 34.0)
		pts.append(Vector2(x, y))
		if branch_from == Vector2.ZERO and y > 120.0 and _dice.randf() < 0.4:
			branch_from = Vector2(x, y)
	var lines: Array = [[pts, 1.0]]
	if branch_from != Vector2.ZERO:
		var b := PackedVector2Array([branch_from])
		var dir := -1.0 if _dice.randf() < 0.5 else 1.0
		for i in 3:
			b.append(b[-1] + Vector2(dir * _dice.randf_range(14.0, 30.0), _dice.randf_range(18.0, 34.0)))
		lines.append([b, 0.55])
	for e in lines:
		for pass_ in 2:   # a wide soft glow under a thin bright core
			var ln := Line2D.new()
			ln.points = e[0]
			ln.width = (7.0 if pass_ == 0 else 2.0) * float(e[1])
			ln.default_color = Color(0.7, 0.8, 1.0, 0.25) if pass_ == 0 else Color(0.95, 0.97, 1.0, 0.95)
			ln.joint_mode = Line2D.LINE_JOINT_ROUND
			_bolt.add_child(ln)

func _update_lightning(delta: float) -> void:
	var l: Dictionary = _cfg.lightning
	var strength := float(l.strength)
	if _strike_t < 0.0:
		_strike_at -= delta
		if _strike_at <= 0.0:
			_strike_t = 0.0
			_new_bolt()
		return
	_strike_t += delta
	# pulses: (start, height, decay time) - the main flash, then flickers
	var level := 0.0
	var core := 0.0
	for p in [[0.0, 1.0, 0.22], [0.2, 0.6, 0.26], [0.55, 0.3, 0.4]]:
		var d: float = _strike_t - p[0]
		if d >= 0.0:
			var v: float = clampf(d / 0.03, 0.0, 1.0) * exp(-d / float(p[2])) * float(p[1])
			level = maxf(level, v)
			if p[0] < 0.5:
				core = maxf(core, v)
	_flash.color.a = level * strength
	_bolt.modulate.a = clampf(core * 1.4, 0.0, 1.0)
	if _strike_t > 1.8:
		_strike_t = -1.0
		_flash.color.a = 0.0
		_bolt.modulate.a = 0.0
		_strike_at = _dice.randf_range(float(l.interval[0]), float(l.interval[1]))

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
	m.set_shader_parameter("brightness", float(g.get("brightness", 1.0)))
	r.material = m
	layer.add_child(r)

func _physics_process(delta: float) -> void:
	_t += delta
	var vr := _lv.view_rect()
	_fog_back.global_position = vr.position
	_fog_back_mat.set_shader_parameter("scroll", Vector2(vr.position.x * 0.85, 0.0))
	_fog_front_mat.set_shader_parameter("scroll", Vector2(vr.position.x * 1.25, 0.0))
	for i in _lamps.size():
		var l: Dictionary = _cfg.lamps[i]
		var f := float(l.flicker)
		_lamps[i].modulate.a = float(l.alpha) * (1.0 - f * 0.5 + f * 0.5 * sin(_t * (5.0 + 1.3 * i) + 2.1 * i) * sin(_t * (2.3 + 0.7 * i)))
	if _moon != null:
		var far := _lv.far_sprite()
		_moon.position = far.position + Vector2(float(_cfg.moon.x), float(_cfg.moon.y))
		for i in _shafts.size():
			_shafts[i].modulate.a = 0.55 + 0.45 * sin(_t * (0.35 + 0.11 * i) + 1.7 * i)
		_moon_glow.modulate.a = 0.26 + 0.05 * sin(_t * 0.6)
	if _rain_mat != null:
		_rain_mat.set_shader_parameter("scroll", vr.position.x)   # the rain stays where it is in the world
	if _flash != null:
		_update_lightning(delta)
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
