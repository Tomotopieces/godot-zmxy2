extends Node
## Turns a stage's scenery (assets/levels/<stage>/level.json) into a scene to arrange by hand in the editor:
##   godot --headless --path game res://tools/level_to_scene.tscn -- sl12 [--force] [--far=1_v6:35] [--fog=1_v6:45,1_v6:60] [--near=1_v6:50]
## writes res://scenes/levels/<stage>.tscn, which Level then uses instead of the art of level.json:
##   Scenery
##     Guides          reference lines for the editor only (the first screen, the floor); dropped when the stage runs
##     Art             behind the actors
##       Far           Parallax2D, scroll 0.8: distant silhouettes (the keys of --far)
##       <Fog...>      TextureRects (the keys of --fog): haze bands that run the length of the stage, at the speed of the ground
##       Middle        Parallax2D, scroll 0.9: the decoration
##       Near          Parallax2D, scroll 1.0: what the player passes close by - the tall pieces around a door, and --near
##     Ground          the floor
## A Parallax2D layer at scroll s moves with s of the camera, so what it holds is placed at s * (the original x): standing
## in front of a piece (the camera at its place) it is where the original had it, and the further the camera is from it
## the slower it slides. The original's pieces are placed one Sprite2D per bitmap rectangle; a row of the same picture
## laid side by side (haze, floor) is one TextureRect with tiling instead (repeat on, stretch mode Tile, texture filter Nearest): no seams, one node.
## Nothing is regenerated once the scene exists (this tool refuses to overwrite it without --force).

const FLOOR_Y := 497.0
const SCROLL := {"Far": 0.8, "Middle": 0.9, "Near": 1.0}
const TALL := 250.0           ## a piece this tall next to a door goes in the near layer

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var stage := String(args[0])
	var out := "res://scenes/levels/%s.tscn" % stage
	if ResourceLoader.exists(out) and not "--force" in args:
		print("%s exists: not overwritten (use --force)" % out)
		get_tree().quit(1)
		return
	var far_keys := _keys(args, "--far=")
	var fog_keys := _keys(args, "--fog=")
	var near_keys := _keys(args, "--near=")
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
	var layers := {}
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.z_index = Layers.Z_GROUND
	root.add_child(ground)

	# every piece: its place (the transform of a Sprite2D at the origin of its bitmap), the part of the bitmap, the tint
	var pieces: Array = []
	for i in d.art.size():
		var leaf: Array = d.art[i]
		var info: Dictionary = d.textures[leaf[0]]
		var tex: Texture2D = load(info.res)
		var s := 1.0 / float(info.scale)
		var m: Array = leaf[1]
		var xf := Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5])) * Transform2D(Vector2(s, 0), Vector2(0, s), Vector2(info.ox, info.oy))
		var r := Rect2(0, 0, tex.get_width(), tex.get_height())
		var repeat := false
		if leaf.size() > 4:
			r = Rect2(leaf[4][0], leaf[4][1], leaf[4][2], leaf[4][3])
			repeat = int(leaf[4][4]) == 1
		var tint = null
		if leaf[2] != null:
			var ct: Array = leaf[2]
			tint = Color(ct[0] + ct[4] / 255.0, ct[1] + ct[5] / 255.0, ct[2] + ct[6] / 255.0, clampf(ct[3] + ct[7] / 255.0, 0, 1))
		pieces.append({"key": String(leaf[0]), "tex": tex, "xf": xf, "region": r, "repeat": repeat, "tint": tint,
				"ground": leaf.size() > 3 and leaf[3] == 1, "n": i, "run": -1})
	# which layer: the floor, the fog bands, the far silhouettes; tall pieces around a door (and --near) are near; the rest middle
	for p in pieces:
		var box := Rect2(p.xf.origin, p.region.size * p.xf.get_scale().abs())
		var layer := "Middle"
		if p.ground:
			layer = "Ground"
		elif p.key in fog_keys:
			layer = "Fog"
		elif p.key in far_keys:
			layer = "Far"
		elif p.key in near_keys or _by_a_door(d, box):
			layer = "Near"
		p["layer"] = layer
	_find_runs(pieces)

	var counters := {}
	var fog_nodes: Array = []
	var made := 0
	var run_seen := {}
	for p in pieces:
		var layer: String = p.layer
		var k := 1.0
		if layer != "Ground" and layer != "Fog":
			k = SCROLL[layer]
			if not layers.has(layer):
				var px := Parallax2D.new()
				px.name = layer
				px.scroll_scale = Vector2(k, 1.0)
				layers[layer] = px
		if p.run >= 0:
			if run_seen.has(p.run):
				continue
			run_seen[p.run] = true
		var node: CanvasItem = _make_rect(p, pieces, k) if p.run >= 0 else _make_sprite(p, k)
		var base := String(p.key).replace(":", "_").replace("1_v6_", "b")
		if p.run >= 0:
			base = {"Ground": "Tile", "Fog": "Fog"}.get(layer, base + "_Tiles")
			counters[base] = int(counters.get(base, 0)) + 1
			node.name = base if counters[base] == 1 else "%s%d" % [base, counters[base]]
		else:
			node.name = "%s_%02d" % [base, p.n]
		if layer == "Ground":
			ground.add_child(node)
		elif layer == "Fog":
			fog_nodes.append(node)
		else:
			layers[layer].add_child(node)
		made += 1
	# behind to front: far, the fog bands, middle, near
	for nm in ["Far", "Fog", "Middle", "Near"]:
		if nm == "Fog":
			for c in fog_nodes:
				art.add_child(c)
		elif layers.has(nm):
			art.add_child(layers[nm])
	_own(root, root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/levels"))
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, out)
	print("%s: %s (%d nodes from %d pieces)" % [out, "saved" if err == OK else "ERROR %d" % err, made, pieces.size()])
	get_tree().quit(0 if err == OK else 1)

func _keys(args: PackedStringArray, prefix: String) -> PackedStringArray:
	for a in args:
		if String(a).begins_with(prefix):
			return String(a).substr(prefix.length()).split(",")
	return PackedStringArray()

## A tall piece (a tree, a gate, a statue) standing at an exit door, or in the way of another door's frame.
func _by_a_door(d: Dictionary, box: Rect2) -> bool:
	if box.size.y < TALL:
		return false
	for dd in d.doors:
		var r := Rect2(dd.rect[0], dd.rect[1], dd.rect[2], dd.rect[3])
		if dd.kind == "exit_door":
			r = Rect2(r.position.x - 600.0, r.position.y, r.size.x + 850.0, r.size.y)   # the approach to the door, and just past it
		if box.position.x < r.end.x and box.end.x > r.position.x:
			return true
	return false

## Pieces of one picture laid side by side along a line (same size, same row, edge to edge) are one run: marks p.run.
## Floor and fog strips may overlap as much as they like (they are a pattern); decoration only by a few px (a bitmap
## laid over itself is two objects, not a tile).
func _find_runs(pieces: Array) -> void:
	var groups := {}
	for p in pieces:
		var xf: Transform2D = p.xf
		var tex_size: Vector2 = p.tex.get_size()
		var whole: bool = p.repeat or (p.region.position.is_zero_approx() and p.region.size.distance_to(tex_size) < 0.6)
		if not (absf(xf.x.y) < 1e-6 and absf(xf.y.x) < 1e-6 and xf.x.x > 0.0 and absf(xf.x.x - xf.y.y) < 1e-6 and whole):
			continue
		var g := "%s|%.3f|%s|%s|%s" % [p.key, xf.x.x, p.region.size, p.layer, p.tint]
		if not groups.has(g):
			groups[g] = []
		groups[g].append(p)
	var run_id := 0
	for g in groups:
		var list: Array = groups[g]
		list.sort_custom(func(a, b): return a.xf.origin.x < b.xf.origin.x)
		var loose: bool = list[0].layer == "Ground" or list[0].layer == "Fog"
		var chains: Array = []
		for p in list:
			var joined := false
			for chain in chains:
				var last: Dictionary = chain[-1]
				var end_x: float = chain.reduce(func(m, q): return maxf(m, q.xf.origin.x + q.region.size.x * q.xf.x.x), -1e9)
				var gap: float = p.xf.origin.x - end_x
				var low := -1e9 if loose else -8.0
				var step: float = p.xf.origin.x - last.xf.origin.x
				if absf(p.xf.origin.y - last.xf.origin.y) <= 1.6 and gap <= 1.6 and gap >= low and step > 0.5:
					chain.append(p)
					joined = true
					break
			if not joined:
				chains.append([p])
		for chain in chains:
			if chain.size() >= 3:
				for p in chain:
					p.run = run_id
				run_id += 1

func _make_sprite(p: Dictionary, k: float) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = false
	sp.texture = p.tex
	var xf: Transform2D = p.xf
	xf.origin.x *= k
	sp.transform = xf
	sp.region_enabled = true
	sp.region_rect = p.region
	if p.repeat:
		sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if p.tint != null:
		sp.modulate = p.tint
	return sp

## One TextureRect tiling the whole run: from the first piece's corner to the last piece's far edge.
func _make_rect(p: Dictionary, pieces: Array, k: float) -> TextureRect:
	var first: Dictionary = p
	var end_x := -1e9
	for q in pieces:
		if q.run == p.run:
			if q.xf.origin.x < first.xf.origin.x:
				first = q
			end_x = maxf(end_x, q.xf.origin.x + q.region.size.x * q.xf.x.x)
	var sc: float = first.xf.x.x
	var tr := TextureRect.new()
	tr.texture = first.tex
	tr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # a tiling TextureRect needs Nearest: linear filtering blends the tile edges
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.position = Vector2(first.xf.origin.x * k, first.xf.origin.y)
	tr.size = Vector2((end_x - first.xf.origin.x) / sc, first.region.size.y)
	if not is_equal_approx(sc, 1.0):
		tr.scale = Vector2(sc, sc)
	if first.tint != null:
		tr.modulate = first.tint
	return tr

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
