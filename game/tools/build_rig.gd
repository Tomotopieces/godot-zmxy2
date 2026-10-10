extends SceneTree
## Build a cutout rig scene from rig.json (written by tools/rig/extract_rig.js).
##
##   godot --headless --path game --import
##   godot --headless --path game -s res://tools/build_rig.gd -- res://assets/rigs/wukong/rig.json [...]
##
## Output next to the json: <name>.tscn, anims.res, slots/*.tscn

const RigScript := preload("res://src/rig/rig.gd")
const SlotScript := preload("res://src/rig/equip_slot.gd")
const FilterShader := preload("res://src/rig/flash_filter.gdshader")

var _d: Dictionary
var _fps := 24.0
var _dir := ""
var _tex := {}
var _add_mat: CanvasItemMaterial

func _add_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat

var _materials := {}   ## filter id -> ShaderMaterial (shared within one rig)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		_build(a)
	quit()

func _texture(key: String) -> Texture2D:
	if not _tex.has(key):
		var info = _d.textures.get(key)
		_tex[key] = load(info.res) if info else null
		if _tex[key] == null:
			push_error("missing texture " + key)
	return _tex[key]

## leaf matrix [a,b,c,d,tx,ty] (+ png offset/scale for textures) -> Transform2D
func _xf(m: Array, key := "") -> Transform2D:
	var t := Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
	if key != "":
		var info = _d.textures[key]
		var s := 1.0 / float(info.scale)
		t = t * Transform2D(Vector2(s, 0), Vector2(0, s), Vector2(info.ox, info.oy))
	return t

## Flash color transform -> modulate (additive terms approximated as extra brightness)
func _mod(ct) -> Color:
	if ct == null:
		return Color.WHITE
	return Color(ct[0] + ct[4] / 255.0, ct[1] + ct[5] / 255.0, ct[2] + ct[6] / 255.0, clampf(ct[3] + ct[7] / 255.0, 0, 1))

func _vtrack(a: Animation, path: String) -> int:
	var i := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(i, NodePath(path))
	a.value_track_set_update_mode(i, Animation.UPDATE_DISCRETE)
	a.track_set_interpolation_type(i, Animation.INTERPOLATION_NEAREST)
	return i

func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)

# ------------------------------------------------------------------ filters

## Flash filters of one display object -> material for the CanvasGroup that renders it.
func _filter_material(fid: int) -> ShaderMaterial:
	if _materials.has(fid):
		return _materials[fid]
	var m := ShaderMaterial.new()
	m.shader = FilterShader
	for f in _d.filters[fid]:
		match f.t:
			"blur":
				if f.x == 0 and f.y == 0:
					continue   # a later no-op must not wipe an earlier filter of the chain
				m.set_shader_parameter("blur", Vector2(f.x, f.y))
			"glow":
				if f.s == 0 or not f.has("c"):
					continue
				m.set_shader_parameter("glow_on", true)
				m.set_shader_parameter("glow_blur", Vector2(f.x, f.y))
				m.set_shader_parameter("glow_strength", f.s)
				m.set_shader_parameter("glow_color", Color(f.c[0] / 255.0, f.c[1] / 255.0, f.c[2] / 255.0, f.c[3] / 255.0))
				m.set_shader_parameter("glow_inner", f.inner)
				m.set_shader_parameter("glow_knockout", f.knockout)
			"matrix":
				var a: Array = f.m
				m.set_shader_parameter("matrix_on", true)
				m.set_shader_parameter("color_matrix", Projection(
					Vector4(a[0], a[5], a[10], a[15]), Vector4(a[1], a[6], a[11], a[16]),
					Vector4(a[2], a[7], a[12], a[17]), Vector4(a[3], a[8], a[13], a[18])))
				m.set_shader_parameter("color_offset", Vector4(a[4], a[9], a[14], a[19]) / 255.0)
	_materials[fid] = m
	return m

## Margin the CanvasGroup needs around its content so blur and glow are not cut off.
func _filter_margin(fid: int) -> float:
	var r := 4.0
	for f in _d.filters[fid]:
		if f.t != "matrix":
			r += maxf(f.x, f.y)
	return r

## Parent for a filtered layer: one CanvasGroup per (group, filter) under `parent`.
func _filter_group(parent: Node2D, group: String, fid: int) -> Node2D:
	var gname := "g%s_f%d" % [group.replace(".", "_"), fid]
	var g := parent.get_node_or_null(gname) as Node2D
	if g == null:
		var cg := CanvasGroup.new()
		cg.name = gname
		cg.use_mipmaps = false
		cg.fit_margin = _filter_margin(fid)
		cg.clear_margin = Rig.filter_clear_margin(cg.fit_margin)
		cg.material = _filter_material(fid)
		parent.add_child(cg)
		g = cg
	return g

# ------------------------------------------------------------------ slot variants

func _variant_scene(sel: String, id: String, v: Dictionary) -> PackedScene:
	var frames: Array = v.frames
	var any := false
	for fr in frames:
		if fr.size() > 0:
			any = true
	if not any:
		return null
	var root := Node2D.new()
	root.name = "Slot%s_%s" % [sel, id]
	var nodes := {}   ## leaf key (path + filter) -> Sprite2D
	var key := func(lf: Array) -> String:
		return String(lf[0]) + ("" if lf.size() < 5 or lf[4] == null else "|f%d" % int(lf[4]))
	for fr in frames:
		for lf in fr:
			var k: String = key.call(lf)
			if not nodes.has(k):
				var sp := Sprite2D.new()
				sp.name = "p" + k.replace(".", "_").replace("|", "_")
				sp.centered = false
				sp.texture = _texture(lf[1])
				sp.transform = _xf(lf[2], lf[1])
				sp.modulate = _mod(lf[3])
				var parent: Node2D = root
				if lf.size() > 4 and lf[4] != null:
					parent = _filter_group(root, String(lf[5]), int(lf[4]))
				parent.add_child(sp)
				nodes[k] = sp
	if frames.size() > 1:
		var ap := AnimationPlayer.new()
		ap.name = "Anim"
		root.add_child(ap)
		var an := Animation.new()
		an.length = frames.size() / _fps
		an.loop_mode = Animation.LOOP_LINEAR
		for p in nodes:
			var np := String(root.get_path_to(nodes[p]))
			var tv := _vtrack(an, np + ":visible")
			var tt := _vtrack(an, np + ":texture")
			var tf := _vtrack(an, np + ":transform")
			var tm := _vtrack(an, np + ":modulate")
			for f in frames.size():
				var hit = null
				for lf in frames[f]:
					if key.call(lf) == p:
						hit = lf
				var t := f / _fps
				an.track_insert_key(tv, t, hit != null)
				if hit != null:
					an.track_insert_key(tt, t, _texture(hit[1]))
					an.track_insert_key(tf, t, _xf(hit[2], hit[1]))
					an.track_insert_key(tm, t, _mod(hit[3]))
		var lib := AnimationLibrary.new()
		lib.add_animation(&"loop", an)
		ap.add_animation_library(&"", lib)
		ap.autoplay = "loop"
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var path := "%s/slots/slot%s_%s.tscn" % [_dir, sel, id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir + "/slots"))
	ResourceSaver.save(ps, path)
	root.free()
	return load(path)

## A Flash layer may swap symbols mid-action (e.g. weapon -> arm piece). Slot nodes are typed by their
## symbol, so every symbol of a slot track gets its own track, hidden while another symbol is shown.
func _split_slot_tracks(tracks: Array) -> Array:
	var out := []
	for tr in tracks:
		if tr.kind != "slot":
			out.append(tr)
			continue
		var sels := []
		for k in tr.keys:
			if k[1] != null and not sels.has(int(k[1])):
				sels.append(int(k[1]))
		for sel in sels:
			var keys := []
			for k in tr.keys:
				if k[1] != null and int(k[1]) == sel:
					keys.append(k)
				elif keys.is_empty() or keys[-1][1] != null:
					keys.append([k[0], null, null, null])
			out.append({"path": tr.path, "kind": "slot", "sel": sel, "keys": keys, "filter": tr.get("filter"), "group": tr.get("group")})
	return out

# ------------------------------------------------------------------ main

func _build(json_path: String) -> void:
	_d = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if _d == null:
		push_error("bad rig json " + json_path)
		return
	_fps = float(_d.fps)
	_dir = json_path.get_base_dir()
	_tex.clear()
	_materials.clear()

	# slot variant scenes
	var slot_scenes := {}
	for sel in _d.slots:
		var vs := {}
		for id in _d.slots[sel].variants:
			var ps := _variant_scene(sel, id, _d.slots[sel].variants[id])
			if ps:
				vs[int(id)] = ps
		slot_scenes[sel] = vs

	var root := Node2D.new()
	root.name = String(_d.name).to_pascal_case()
	root.set_script(RigScript)
	var parts := Node2D.new()
	parts.name = "Parts"
	root.add_child(parts)
	var boxes := {}
	for bn in ["Hitbox", "Hurtbox"]:
		var area := Area2D.new()
		area.name = bn
		area.monitoring = bn == "Hitbox"
		area.monitorable = bn == "Hurtbox"
		area.collision_layer = 0
		area.collision_mask = 0
		var cs := CollisionShape2D.new()
		cs.name = "Shape"
		var rs := RectangleShape2D.new()
		rs.resource_local_to_scene = true
		cs.shape = rs
		cs.disabled = true
		area.add_child(cs)
		root.add_child(area)
		boxes[bn] = cs
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	root.add_child(ap)

	var lib := AnimationLibrary.new()
	var names := PackedStringArray()
	# Rigs without any stick hitbox (projectiles, skill effects) hit with their whole art bounds.
	var art_hits := true
	for act_name in _d.actions:
		for k in _d.actions[act_name].hit + _d.actions[act_name].hurt:
			if k[1] != null:
				art_hits = false
	for act_name in _d.actions:
		var act: Dictionary = _d.actions[act_name]
		names.append(act_name)
		var cont := Node2D.new()
		cont.name = act_name
		cont.visible = false
		parts.add_child(cont)
		var an := Animation.new()
		an.length = act.frames / _fps
		an.loop_mode = Animation.LOOP_LINEAR if act.loop else Animation.LOOP_NONE
		if act.has("loop_from"):
			an.set_meta(&"loop_from", float(act.loop_from) / _fps)   # Rig keeps looping the tail

		for tr in _split_slot_tracks(act.tracks):
			if tr.kind != "tex" and tr.kind != "slot":
				continue
			var nn: String = "p" + String(tr.path).replace(".", "_") + (("_s%d" % tr.sel) if tr.kind == "slot" else "")
			var parent: Node2D = cont
			if tr.get("filter") != null:
				nn += "_f%d" % int(tr.filter)
				parent = _filter_group(cont, String(tr.group), int(tr.filter))
			var node: Node2D
			if tr.kind == "tex":
				var sp := Sprite2D.new()
				sp.centered = false
				node = sp
			else:
				var es := Node2D.new()
				es.set_script(SlotScript)
				node = es
			node.name = nn
			if int(tr.get("blend", 0)) == 8:   # Flash "add": light drawn on black
				node.material = _add_material()
			parent.add_child(node)
			var np := "Parts/%s/%s" % [act_name, String(cont.get_path_to(node))]
			var tv := _vtrack(an, np + ":visible")
			var tt := _vtrack(an, np + ":texture") if tr.kind == "tex" else -1
			var tf := _vtrack(an, np + ":transform")
			var tm := _vtrack(an, np + ":modulate")
			var first = null
			if int(tr.keys[0][0]) > 0:
				an.track_insert_key(tv, 0.0, false)
			# Flash mask crop -> texture region (+ offset so the region stays in place)
			var cropped := false
			for k in tr.keys:
				if k.size() > 4 and k[4] != null:
					cropped = true
			var treg := -1
			var toff := -1
			if cropped and tr.kind == "tex":
				node.region_enabled = true
				treg = _vtrack(an, np + ":region_rect")
				toff = _vtrack(an, np + ":offset")
			for k in tr.keys:
				var t: float = k[0] / _fps
				if k[1] == null:
					an.track_insert_key(tv, t, false)
					continue
				if treg >= 0:
					var tex := _texture(k[1])
					var full := Rect2(Vector2.ZERO, tex.get_size())
					var reg := full
					if k.size() > 4 and k[4] != null:
						var c: Array = k[4]
						reg = (_xf(k[2], k[1]).affine_inverse() * Rect2(c[0], c[1], c[2], c[3])).intersection(full)
					an.track_insert_key(treg, t, reg)
					an.track_insert_key(toff, t, reg.position)
					if reg.size.x < 1.0 or reg.size.y < 1.0:
						an.track_insert_key(tv, t, false)
						continue
				an.track_insert_key(tv, t, true)
				if tr.kind == "tex":
					an.track_insert_key(tt, t, _texture(k[1]))
					an.track_insert_key(tf, t, _xf(k[2], k[1]))
				else:
					an.track_insert_key(tf, t, _xf(k[2]))
				an.track_insert_key(tm, t, _mod(k[3]))
				if first == null:
					first = k
			# rest pose = first visible key (editor preview)
			if first != null:
				if tr.kind == "tex":
					node.texture = _texture(first[1])
					node.transform = _xf(first[2], first[1])
				else:
					var sel := str(int(first[1]))
					node.kind = _d.slots[sel].kind
					node.variants = slot_scenes.get(sel, {})
					node.variant_id = 1
					node.transform = _xf(first[2])
				node.modulate = _mod(first[3])

		# hit / hurt boxes
		for pair in [["Hitbox", act.art if art_hits else act.hit], ["Hurtbox", act.hurt]]:
			var base: String = pair[0] + "/Shape"
			var tp := _vtrack(an, base + ":position")
			var ts := _vtrack(an, base + ":shape:size")
			var td := _vtrack(an, base + ":disabled")
			for k in pair[1]:
				var t2: float = k[0] / _fps
				var r = k[1]
				if r == null:
					an.track_insert_key(td, t2, true)
				else:
					an.track_insert_key(td, t2, false)
					an.track_insert_key(tp, t2, Vector2(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0))
					an.track_insert_key(ts, t2, Vector2(maxf(r[2], 1), maxf(r[3], 1)))

		# gameplay events: method track on the rig root, one key per frame carrying all of its events
		# (a track holds one key per time); frame-0 events are emitted by Rig.play()
		var tev := an.add_track(Animation.TYPE_METHOD)
		an.track_set_path(tev, NodePath("."))
		var by_frame := {}
		for e in act.events:
			var f := int(e[0])
			if not by_frame.has(f):
				by_frame[f] = []
			by_frame[f].append([StringName(e[1]), e.slice(2)])
		for f in by_frame:
			if f > 0:
				an.track_insert_key(tev, f / _fps, {"method": &"_anim_events", "args": [by_frame[f]]})
		an.set_meta(&"start_events", by_frame.get(0, []))
		lib.add_animation(StringName(act_name), an)

	var lib_path := _dir + "/anims.res"
	ResourceSaver.save(lib, lib_path, ResourceSaver.FLAG_COMPRESS)
	ap.add_animation_library(&"", load(lib_path))
	root.actions = names
	var rest: Dictionary = _d.actions.get("wait", _d.actions.values()[0])
	for mk in rest.markers:
		var p: Array = rest.markers[mk][0]
		root.markers[mk] = Vector2(p[1], p[2])
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %d" % err)
	var out := "%s/%s.tscn" % [_dir, _d.name]
	ResourceSaver.save(ps, out)
	root.free()
	print("built ", out, " actions=", names.size(), " slots=", slot_scenes.size())
