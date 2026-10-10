extends Node
## Stage art screenshots (art only, deterministic): godot --path game --position 6000,6000 res://tools/stage_shot.tscn -- <stage,level> <out.png> <x,x,...>
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	GameState.new_game("wukong")
	var ps := PlayScreen.create(Vector2i(int(a[0].get_slice(",", 0)), int(a[0].get_slice(",", 1)))); add_child(ps)
	await get_tree().create_timer(1.0, false).timeout
	var lv := ps.level
	lv.process_mode = Node.PROCESS_MODE_DISABLED
	lv.hero.visible = false
	lv.camera.enabled = false
	var xs := a[2].split(",")
	var shots: Array[Image] = []
	for x in xs:
		lv.world.position.x = -float(x)
		lv._far.position.x = -float(x) * (lv._far_width - Layers.VIEW.x) / (lv._end_x - Layers.VIEW.x)
		for i in 3: await RenderingServer.frame_post_draw
		shots.append(get_viewport().get_texture().get_image())
	var sheet := Image.create(940 * 2, 590 * ((shots.size() + 1) / 2), false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, 940, 590), Vector2i(940 * (i % 2), 590 * (i / 2)))
	sheet.save_png(a[1])
	get_tree().quit()
