extends Node
## Turns a stage's scenery (assets/levels/<stage>/level.json) into a scene to arrange by hand in the editor:
##   godot --headless --path game res://tools/level_to_scene.tscn -- sl11 [--force] [--far=1_v6:84,1_v6:85]
## writes res://scenes/levels/<stage>.tscn, which Level then uses instead of the art of level.json:
##   Scenery
##     Guides          reference lines for the editor only (the first screen, the floor); dropped when the stage runs
##     Art             behind the actors
##       Far           Parallax2D, scroll 0.6: the distant layer (the pictures named by --far, if any)
##       Near          Parallax2D, scroll 1.0: the rest of the scenery as the original had it (moves with the ground)
##     Ground          the floor
## One piece of art = one Sprite2D with its picture, place and tint; edit the scene as you like. Nothing is regenerated
## once the scene exists (this tool refuses to overwrite it without --force).

const FLOOR_Y := 497.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var stage := String(args[0])
	var out := "res://scenes/levels/%s.tscn" % stage
	if ResourceLoader.exists(out) and not "--force" in args:
		print("%s exists: not overwritten (use --force)" % out)
		get_tree().quit(1)
		return
	var far_keys: PackedStringArray = []
	for a in args:
		if String(a).begins_with("--far="):
			far_keys = String(a).substr(6).split(",")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/levels/%s/level.json" % stage))
	var root := Node2D.new()
	root.name = "Scenery"
	var guides := Node2D.new()
	guides.name = "Guides"
	root.add_child(guides)
	_line(guides, "Floor", [Vector2(-200, FLOOR_Y), Vector2(d.size[0] + 200.0, FLOOR_Y)], Color(1, 0.3, 0.2, 0.8))
	_line(guides, "FirstScreen", [Vector2(0, 0), Vector2(940, 0), Vector2(940, 590), Vector2(0, 590), Vector2(0, 0)], Color(0.3, 1, 0.4, 0.8))
	var art := Node2D.new()
	art.name = "Art"
	art.z_index = Layers.Z_ART
	root.add_child(art)
	var far := Parallax2D.new()
	far.name = "Far"
	far.scroll_scale = Vector2(0.6, 1.0)
	art.add_child(far)
	var near := Parallax2D.new()
	near.name = "Near"
	near.scroll_scale = Vector2(1.0, 1.0)
	art.add_child(near)
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.z_index = Layers.Z_GROUND
	root.add_child(ground)
	var n := 0
	for leaf in d.art:
		var info: Dictionary = d.textures[leaf[0]]
		var sp := Sprite2D.new()
		sp.centered = false
		sp.texture = load(info.res)
		var s := 1.0 / float(info.scale)
		var m: Array = leaf[1]
		sp.transform = Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5])) * Transform2D(Vector2(s, 0), Vector2(0, s), Vector2(info.ox, info.oy))
		if leaf.size() > 4:
			var r: Array = leaf[4]
			sp.region_enabled = true
			sp.region_rect = Rect2(r[0], r[1], r[2], r[3])
			if int(r[4]) == 1:
				sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		if leaf[2] != null:
			var ct: Array = leaf[2]
			sp.modulate = Color(ct[0] + ct[4] / 255.0, ct[1] + ct[5] / 255.0, ct[2] + ct[6] / 255.0, clampf(ct[3] + ct[7] / 255.0, 0, 1))
		var is_ground: bool = leaf.size() > 3 and leaf[3] == 1
		# named after the original bitmap (1_v6:47 -> b47_03), numbered in painting order
		sp.name = "%s_%02d" % [String(leaf[0]).replace(":", "_").replace("1_v6_", "b"), n]
		n += 1
		(ground if is_ground else (far if leaf[0] in far_keys else near)).add_child(sp)
	_own(root, root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/levels"))
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, out)
	print("%s: %s (%d sprites)" % [out, "saved" if err == OK else "ERROR %d" % err, n])
	get_tree().quit(0 if err == OK else 1)

func _line(parent: Node, nm: String, pts: Array, color: Color) -> void:
	var l := Line2D.new()
	l.name = nm
	l.points = PackedVector2Array(pts)
	l.width = 2.0
	l.default_color = color
	parent.add_child(l)

func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_own(c, root)
