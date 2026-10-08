extends Node2D
## Render rig actions to a PNG: godot --path game res://tools/rig_shot.tscn -- <rig> <out.png> <action,action,...> [scale]
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var acts := a[2].split(",")
	var s := float(a[3]) if a.size() > 3 else 1.0
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.4, 0.45)
	bg.size = Vector2(940, 590)
	add_child(bg)
	for i in acts.size():
		var r := Rig.create(a[0])
		r.position = Vector2(470.0 / acts.size() * (i + 0.5) * 2.0 / 2.0 + 470.0 / acts.size() * i, 330)
		r.scale = Vector2(s, s)
		add_child(r)
		r.play(StringName(acts[i]))
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a[1])
	get_tree().quit()
