extends Node2D
## Contact sheet of rigs with effects: godot --path game --position 6000,6000 res://tools/fx_gallery.tscn -- <out.png> <rig,rig,...> [frame] [scale]
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var names := a[1].split(",")
	var frame := int(a[2]) if a.size() > 2 else 3
	var s := float(a[3]) if a.size() > 3 else 1.0
	var cols := 4
	var cell := Vector2(260, 220) * s
	var rows := int(ceil(names.size() / float(cols)))
	get_window().size = Vector2i(int(cell.x) * cols, int(cell.y) * rows)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.35, 0.42)
	bg.size = Vector2(cell.x * cols, cell.y * rows)
	add_child(bg)
	var rigs := []
	for i in names.size():
		var r := Rig.create(names[i])
		r.position = Vector2(cell.x * (i % cols) + cell.x * 0.5, cell.y * (i / cols) + cell.y * 0.6)
		r.scale = Vector2(-s, s)
		add_child(r)
		r.play(StringName(r.actions[0]))
		r.pause()
		var l := Label.new()
		l.text = names[i]
		l.position = Vector2(cell.x * (i % cols) + 4, cell.y * (i / cols) + 2)
		add_child(l)
		rigs.append(r)
	for r: Rig in rigs:
		var len := r.anim.current_animation_length
		r.anim.seek(minf(frame / 24.0, len - 0.01), true)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a[0])
	get_tree().quit()
