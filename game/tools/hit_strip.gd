extends Node2D
## Frames of one action side by side with the attack box (red) and hurt box (green):
## godot --path game --position 6000,6000 res://tools/hit_strip.tscn -- <rig> <action> <out.png> <f,f,...> [scale]
var _rigs: Array[Rig] = []
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var s := float(a[4]) if a.size() > 4 else 1.0
	var frames := a[3].split(",")
	var cols := mini(frames.size(), 4)
	var cell := Vector2(420, 300) * s
	var rows := (frames.size() + cols - 1) / cols
	get_window().size = Vector2i(int(cell.x) * cols, int(cell.y) * rows)
	var bg := ColorRect.new(); bg.color = Color(0.25, 0.28, 0.33); bg.size = cell * Vector2(cols, rows); add_child(bg)
	for i in frames.size():
		var r := Rig.create(a[0])
		r.scale = Vector2(-s, s)
		r.position = Vector2(cell.x * (i % cols) + cell.x * 0.62, cell.y * (i / cols) + cell.y * 0.62)
		add_child(r)
		r.play(StringName(a[1]))
		r.pause()
		r.anim.seek(float(frames[i]) / 24.0, true)
		_rigs.append(r)
		var l := Label.new(); l.text = "f" + frames[i]; l.position = Vector2(cell.x * (i % cols) + 4, cell.y * (i / cols) + 2); add_child(l)
	await RenderingServer.frame_post_draw
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a[2])
	get_tree().quit()
func _draw() -> void:
	for r in _rigs:
		var h := r.hit_rect()
		if h.size != Vector2.ZERO:
			draw_rect(h, Color(1, 0.1, 0.1), false, 2.0)
		var u := r.hurt_rect()
		if u.size != Vector2.ZERO:
			draw_rect(u, Color(0.1, 1, 0.1), false, 1.0)
