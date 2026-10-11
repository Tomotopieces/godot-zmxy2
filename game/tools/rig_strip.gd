extends Node2D
## Frames of one action side by side: godot --path game --position 6000,6000 res://tools/rig_strip.tscn -- <rig> <action> <out.png> <frame,frame,...> [scale] [facing]
## frames are original frame numbers (0-based, at the rig's fps); facing 1 = right
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var r := Rig.create(a[0])
	var fps := 24.0
	var frames := a[3].split(",")
	var s := float(a[4]) if a.size() > 4 else 1.0
	var face := int(a[5]) if a.size() > 5 else 1
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.4, 0.45)
	bg.size = Vector2(4000, 1000)
	add_child(bg)
	r.scale = Vector2(s * -face, s)
	r.position = Vector2(140 * s, 200 * s)
	add_child(r)
	r.play(StringName(a[1]))
	r.pause()
	var cw := 470 * s
	var out := Image.create(int(cw) * frames.size(), 295 * int(ceil(s)), false, Image.FORMAT_RGBA8)
	get_window().size = Vector2i(int(cw) * mini(frames.size(), 4), int(295 * s))
	for i in frames.size():
		r.position = Vector2(cw * i + 140 * s, 200 * s)
		r.anim.seek(float(frames[i]) / fps, true)
		await RenderingServer.frame_post_draw
	r.position = Vector2(140 * s, 200 * s)
	# one capture per frame
	for i in frames.size():
		r.anim.seek(float(frames[i]) / fps, true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		out.blit_rect(img, Rect2i(0, 0, int(cw), int(295 * s)), Vector2i(int(cw) * i, 0))
	out.save_png(a[2])
	get_tree().quit()
