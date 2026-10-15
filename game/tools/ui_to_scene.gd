extends Node
## Turns an interface layout (assets/ui/<name>/ui.json, written by tools/rig/extract_ui.js) into a scene to arrange by hand
## in the editor:
##   godot --headless --path game res://tools/ui_to_scene.tscn -- <name|all> [--force]
## writes res://scenes/ui/<name>.tscn, which UiLayout.create() then instantiates instead of building the json:
##   <name>              the layout root (script UiLayout), its whole tree underneath
## The json stays the generator: this tool builds the layout exactly as the game would, hands every node to the editor
## (`owner`), and packs it. Every node keeps the metas the run-time wiring needs: `ui_piece` (the names the code reaches it
## by), `ui_button` (a button's name), `ui_bar` (a bar holder's full / empty travel). UiLayout._wire_from_scene() rebuilds
## the wiring from them, so a node may be moved anywhere by hand - but a button keeps its Up / Over / Down children and a
## bar its Clip / Content.
## Nothing is regenerated once the scene exists (this tool refuses to overwrite it without --force): the scenes are the
## user's to edit.
## `all` = every directory under assets/ui that has a ui.json.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: res://tools/ui_to_scene.tscn -- <name|all> [--force]")
		get_tree().quit(1)
		return
	var names: Array = []
	if args[0] == "all":
		for d in DirAccess.get_directories_at("res://assets/ui"):
			if FileAccess.file_exists("res://assets/ui/%s/ui.json" % d):
				names.append(d)
		names.sort()
	else:
		names.append(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/ui"))
	var made := 0
	var skipped := 0
	for n in names:
		var out := "res://scenes/ui/%s.tscn" % n
		if ResourceLoader.exists(out) and not "--force" in args:
			print("%s exists, skipped (use --force)" % out)
			skipped += 1
			continue
		var json := "res://assets/ui/%s/ui.json" % n
		if not FileAccess.file_exists(json):
			print("%s: no %s" % [out, json])
			skipped += 1
			continue
		var root := UiLayout.new()
		root.name = String(n)
		root.build(json)
		_own(root, root)
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, out)
		print("%s: %s (%d nodes)" % [out, "saved" if err == OK else "ERROR %d" % err, _count(root)])
		if err != OK:
			get_tree().quit(1)
			return
		made += 1
	print("%d saved, %d skipped" % [made, skipped])
	get_tree().quit(0)

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_own(c, root)
