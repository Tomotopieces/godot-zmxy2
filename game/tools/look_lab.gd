extends Node
## Visual lab: renders a stage with experimental looks (lighting, bump-lit sprites, grading, bloom, mist) and saves
## screenshots to compare. Not part of the game.
##   godot --path game --position 6000,6000 res://tools/look_lab.tscn -- <stage a,b> <camera x> <out prefix> <look,look,...>
## looks: base light bump grade bloom rim mist outline all   (optional 5th argument: monster ids to put on the stage)

const LIT := preload("res://tools/look_lab_lit.gdshader")
const GRADE := preload("res://tools/look_lab_grade.gdshader")

var _lv: Level

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var st := Vector2i(int(a[0].get_slice(",", 0)), int(a[0].get_slice(",", 1)))
	var cam_x := float(a[1])
	var out := a[2]
	var looks: PackedStringArray = a[3].split(",")
	GameState.new_game("wukong")
	var ps := PlayScreen.create(st)
	add_child(ps)
	await get_tree().create_timer(1.0, false).timeout
	_lv = ps.level
	_lv.process_mode = Node.PROCESS_MODE_DISABLED
	ps.hud.visible = false
	_lv.camera.enabled = false
	_lv.world.position.x = -cam_x
	_lv.hero.global_position = Vector2(330.0, 470.0)
	_lv.hero.visible = true
	if a.size() > 4:
		var x := 560.0
		for id in a[4].split(","):
			var m := Monster.create(_lv.monster_data(int(id)))
			_lv.add_monster(m)
			m.global_position = Vector2(x, 440.0)
			x += 190.0
		await get_tree().create_timer(0.3, false).timeout
		for m: Monster in _lv.monsters():
			m.process_mode = Node.PROCESS_MODE_DISABLED
	for look in looks:
		await _apply(look)
	for i in 5:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, a[3].replace(",", "+")])
	get_tree().quit()

func _apply(look: String) -> void:
	match look:
		"light":
			_lights()
		"bump":
			_bump()
		"rim":
			_bump(true)
		"grade":
			_grade()
		"bloom":
			_bloom()
		"mist":
			_mist()
		"outline":
			_outline()
		"all":
			_bump()
			_lights()
			_grade()
			_bloom()
			_mist()
			_outline()

## Every sprite of the stage gets a bump-lit material (normal map from its own brightness and silhouette).
func _bump(rim := false) -> void:
	for sp: Sprite2D in _lv.world.find_children("*", "Sprite2D", true, false):
		if sp.material == null:
			var m := ShaderMaterial.new()
			m.shader = LIT
			m.set_shader_parameter("rim", 1.0 if rim else 0.0)
			sp.material = m

func _lights() -> void:
	var mod := CanvasModulate.new()
	mod.color = Color(0.55, 0.58, 0.75)
	_lv.world.add_child(mod)
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 512
	tex.height = 512
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	var hero_light := PointLight2D.new()
	hero_light.texture = tex
	hero_light.texture_scale = 2.2
	hero_light.color = Color(1.0, 0.85, 0.65)
	hero_light.energy = 0.9
	hero_light.height = 60.0
	hero_light.range_item_cull_mask = 1   # the scenery (the hero and monsters stay on layer 2)
	hero_light.position = Vector2(0, -60)
	_lv.hero.add_child(hero_light)
	for sp: Sprite2D in _lv.hero.find_children("*", "Sprite2D", true, false):
		sp.light_mask = 2
	# a few warm lamps along the way
	for x in [120.0, 520.0, 900.0]:
		var l := PointLight2D.new()
		l.texture = tex
		l.texture_scale = 2.6
		l.color = Color(1.0, 0.6, 0.3)
		l.energy = 1.1
		l.height = 80.0
		l.global_position = Vector2(x, 300.0)
		_lv.world.add_child(l)

## A thin dark outline around every character: a silhouette copy behind it (the same trick the rage glow uses).
func _outline() -> void:
	var actors: Array = [_lv.hero] + _lv.monsters()
	for a: Actor in actors:
		var halo := Rig.create(a.get("data").rig)
		a.add_child(halo)
		a.move_child(halo, a.rig.get_index())
		halo.mirror(a.rig)
		var mat := SpriteFx.glow_material(Color(0.05, 0.03, 0.08, 1.0), 2.2, 2.5, true)
		for sp: Sprite2D in halo.find_children("*", "Sprite2D", true, false):
			sp.material = mat

func _grade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	var rect := ColorRect.new()
	rect.size = Layers.VIEW
	var m := ShaderMaterial.new()
	m.shader = GRADE
	rect.material = m
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)

func _bloom() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _mist() -> void:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(500, 60)
	p.position = Vector2(470, 500)
	p.direction = Vector2(1, -0.1)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.scale_amount_min = 6.0
	p.scale_amount_max = 14.0
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(0.7, 0.8, 1.0, 0.22))
	g.set_color(1, Color(0.7, 0.8, 1.0, 0.0))
	tex.gradient = g
	p.texture = tex
	p.z_index = 20
	add_child(p)
