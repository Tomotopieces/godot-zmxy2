extends Node
## Make a hand-editable actor scene from a generated rig, once:
##   godot --headless --path game res://tools/rig_to_actor.tscn -- <rig> <out dir res> [--force]
## Writes <out>/<rig>.tscn (root script ActorBody) and <out>/<rig>_actions.tres (text animation library).

func _ready() -> void:
	get_tree().create_timer(60.0, true, false, true).timeout.connect(get_tree().quit.bind(2))
	var args := OS.get_cmdline_user_args()
	var rig_name: String = args[0]
	var out_dir: String = args[1]
	var force := args.has("--force")
	var out_scene := "%s/%s.tscn" % [out_dir, rig_name]
	if ResourceLoader.exists(out_scene) and not force:
		print("exists, skipped: ", out_scene, " (use --force)")
		get_tree().quit(0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var root: Node2D = (load("res://assets/rigs/%s/%s.tscn" % [rig_name, rig_name]) as PackedScene).instantiate()
	root.set_script(load("res://src/actors/actor_body.gd"))
	root.name = rig_name.to_pascal_case()
	var map := {}   # old track node path -> new
	var parts: Node = root.get_node("Parts")
	for cont: Node in parts.get_children():
		var old_c := String(cont.name)
		var new_c := ActorBody.pose_name(old_c)
		var ns := 0
		var np := 0
		var kids := cont.get_children()
		for ch: Node in kids:
			var old := "Parts/%s/%s" % [old_c, ch.name]
			if ch is Sprite2D:
				np += 1
				ch.name = "%sPart%d" % [new_c, np]
			else:
				ns += 1
				ch.name = "%sSlot%d" % [new_c, ns]
			map[old] = "Poses/%s/%s" % [new_c, ch.name]
		cont.name = new_c
	parts.name = "Poses"
	map["Parts"] = "Poses"
	var ap: AnimationPlayer = root.get_node("Anim")
	var src_lib: AnimationLibrary = ap.get_animation_library(&"")
	var lib := AnimationLibrary.new()
	var report := []
	for an_name in src_lib.get_animation_list():
		var an: Animation = src_lib.get_animation(an_name).duplicate(true)
		var events := []   # [time, name, args]
		if an.has_meta(&"start_events"):
			for ev in an.get_meta(&"start_events"):
				events.append([0.0, String(ev[0]), ev[1]])
			an.remove_meta(&"start_events")
		for tr in range(an.get_track_count() - 1, -1, -1):
			if an.track_get_type(tr) == Animation.TYPE_METHOD:
				for k in an.track_get_key_count(tr):
					var t := an.track_get_key_time(tr, k)
					var params: Array = an.method_track_get_params(tr, k)
					for ev in params[0]:
						events.append([t, String(ev[0]), ev[1]])
				an.remove_track(tr)
				continue
			var p := String(an.track_get_path(tr))
			var node_part := p.get_slice(":", 0)
			var prop := p.substr(node_part.length())
			if map.has(node_part):
				an.track_set_path(tr, NodePath(map[node_part] + prop))
		events.sort_custom(func(a, b): return a[0] < b[0])
		var tracks := []   # one method track per event slot at the same time
		var slot_at := {}
		for e in events:
			var key := snappedf(e[0], 0.0001)
			var slot: int = slot_at.get(key, 0)
			slot_at[key] = slot + 1
			while tracks.size() <= slot:
				var nt := an.add_track(Animation.TYPE_METHOD)
				an.track_set_path(nt, NodePath("."))
				tracks.append(nt)
			an.track_insert_key(tracks[slot], e[0], {"method": StringName("ev_" + e[1]), "args": e[2]})
		lib.add_animation(an_name, an)
		report.append("%s=%d" % [an_name, events.size()])
	var lib_path := "%s/%s_actions.tres" % [out_dir, rig_name]
	ResourceSaver.save(lib, lib_path)
	ap.remove_animation_library(&"")
	ap.add_animation_library(&"", load(lib_path))
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, out_scene)
	print("saved ", out_scene, " err=", err, " events ", " ".join(report))
	root.free()
	get_tree().quit(0 if err == OK else 1)

func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		if c.owner == null or c.owner != owner_node:
			if c.scene_file_path == "" or c.get_parent() == owner_node or true:
				c.owner = owner_node
		if c.scene_file_path == "":
			_own(c, owner_node)
