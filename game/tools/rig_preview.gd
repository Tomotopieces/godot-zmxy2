extends Node2D
## Rig preview: shows one rig per action in a grid. Left/Right selects the rig file.

@export var rig_scene: PackedScene = preload("res://assets/rigs/wukong/wukong.tscn")

func _ready() -> void:
	var probe: Rig = rig_scene.instantiate()
	var acts := probe.actions
	probe.free()
	var cols := 6
	for i in acts.size():
		var r: Rig = rig_scene.instantiate()
		r.position = Vector2(80 + (i % cols) * 150, 150 + (i / cols) * 190)
		add_child(r)
		r.play(acts[i])
		r.action_finished.connect(func(a): r.play(a, true))
		var l := Label.new()
		l.text = acts[i]
		l.position = r.position + Vector2(-30, 20)
		l.add_theme_color_override("font_color", Color.BLACK)
		add_child(l)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 940, 590), Color(0.82, 0.86, 0.9))

## `-- --shot=<png> [--at=<seconds>]`: save a screenshot and quit (offline check without the editor)
func _process(_dt: float) -> void:
	var shot := ""
	var at := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--at="):
			at = a.substr(5).to_float()
	if shot != "" and Time.get_ticks_msec() / 1000.0 > at + 0.5:
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
