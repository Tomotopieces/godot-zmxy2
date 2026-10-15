extends Node
## Turns a rig (assets/rigs/<rig>/<rig>.tscn) into a plain scene to place by hand in the editor:
##   godot --headless --path game res://tools/rig_to_object.tscn -- <out res> <RootName> <script res> <Child>=<rig>:<anim> [...]
## Every pair merges one rig into a child node of the root and renames its parts <Child>Part1, <Child>Part2 ... (the
## rig's Parts/default children, in order), so the parts are not hidden and can be arranged in the editor (a Rig hides
## them). The rig's Hitbox / Hurtbox tracks only give the gameplay rectangle: it is stored on the root as
## hit_rect_<child> (lower case) and the tracks are dropped, together with the method track (".") and the Parts:visible
## tracks. The animations are collected in one AnimationPlayer "Anim" (library ""). Nothing else is regenerated.

func _ready() -> void:
	get_tree().quit.call_deferred()   # a script error must not leave the tool running headless
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: res://tools/rig_to_object.tscn -- <out res> <RootName> <script res> <Child>=<rig>:<anim> [...]")
		get_tree().quit(1)
		return
	var out := args[0]
	var root := Node2D.new()
	root.name = args[1]
	root.set_script(load(args[2]))
	var lib := AnimationLibrary.new()
	var anims := PackedStringArray()
	var parts := 0
	for i in range(3, args.size()):
		var spec := args[i]
		var eq := spec.find("=")
		var co := spec.find(":", eq + 1)
		if eq < 0 or co < 0:
			print("%s: not <Child>=<rig>:<anim>" % spec)
			get_tree().quit(1)
			return
		var child_name := spec.substr(0, eq)
		var rig_name := spec.substr(eq + 1, co - eq - 1)
		var anim_name := spec.substr(co + 1)
		var src := (load("res://assets/rigs/%s/%s.tscn" % [rig_name, rig_name]) as PackedScene).instantiate()
		var src_parts := src.get_node("Parts/default")
		var child := Node2D.new()
		child.name = child_name
		root.add_child(child)
		var moved := {}
		var k := 0
		for old: Node2D in src_parts.get_children():
			k += 1
			var new_name := child_name + "Part" + str(k)
			moved[String(old.name)] = new_name
			src_parts.remove_child(old)
			old.name = new_name
			child.add_child(old)
			parts += 1
		var an: Animation = (src.get_node("Anim") as AnimationPlayer).get_animation(&"default").duplicate(true)
		var hit := Rect2()
		var hurt := Rect2()
		for t in range(an.get_track_count() - 1, -1, -1):
			var raw := String(an.track_get_path(t))
			var sep := raw.find(":")
			var node_path := raw if sep < 0 else raw.substr(0, sep)
			var prop := "" if sep < 0 else raw.substr(sep + 1)
			if node_path.begins_with("Parts/default/"):
				var old_name := node_path.substr("Parts/default/".length())
				if moved.has(old_name):
					an.track_set_path(t, NodePath("%s/%s:%s" % [child_name, moved[old_name], prop]))
				else:
					an.remove_track(t)
			elif prop == "disabled" and (node_path.begins_with("Hitbox/Shape") or node_path.begins_with("Hurtbox/Shape")):
				if node_path.begins_with("Hitbox"):
					hit = _active_rect(an, t)
				else:
					hurt = _active_rect(an, t)
				an.remove_track(t)
			else:
				an.remove_track(t)
		lib.add_animation(anim_name, an)
		anims.append(anim_name)
		root.set_meta("hit_rect_" + child_name.to_lower(), hit if hit != Rect2() else hurt)
		src.free()
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	root.add_child(ap)
	ap.add_animation_library("", lib)
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, out)
	root.free()
	print("saved %s parts=%d anims=%s" % [out, parts, ", ".join(anims)])
	get_tree().quit(0 if err == OK else 1)

## The rectangle a shape track holds: its position / size at the first moment the box is switched on.
func _active_rect(an: Animation, shape_track: int) -> Rect2:
	var path := String(an.track_get_path(shape_track)).trim_suffix(":disabled")
	var t := -1.0
	for i in an.track_get_key_count(shape_track):
		if an.track_get_key_value(shape_track, i) == false:
			t = an.track_get_key_time(shape_track, i)
			break
	if t < 0.0:
		return Rect2()
	var p = _value_at(an, path + ":position", t)
	var s = _value_at(an, path + ":shape:size", t)
	if p == null or s == null:
		return Rect2()
	return Rect2(p - s / 2.0, s)

## The value of a value track at the time of the last key at or before it.
func _value_at(an: Animation, path: String, t: float):
	for i in an.get_track_count():
		if String(an.track_get_path(i)) != path:
			continue
		var v = null
		for k in an.track_get_key_count(i):
			if an.track_get_key_time(i, k) > t:
				break
			v = an.track_get_key_value(i, k)
		return v
	return null

func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_own(c, root)
