extends Node
## A stage as played, with its lighting: godot --path game --position 6000,6000 res://tools/light_shot.tscn -- <stage a,b> <out.png> <camera x> [monster ids] [wait s] [strike: lightning at once, shot after that many s]
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	GameState.new_game("wukong")
	var ps := PlayScreen.create(Vector2i(int(a[0].get_slice(",", 0)), int(a[0].get_slice(",", 1))))
	add_child(ps)
	await get_tree().create_timer(1.0, false).timeout
	var lv := ps.level
	lv.hero.global_position = Vector2(float(a[2]) + 330.0, 470.0)
	if a.size() > 3:
		var x := float(a[2]) + 560.0
		for id in a[3].split(","):
			var m := Monster.create(lv.monster_data(int(id)))
			lv.add_monster(m)
			m.global_position = Vector2(x, 440.0)
			x += 170.0
	print("monsters ", lv.monsters().size(), " hero ", lv.hero.global_position)
	await get_tree().create_timer(float(a[4]) if a.size() > 4 else 2.5, false).timeout
	print("monsters ", lv.monsters().size(), " hero ", lv.hero.global_position, " ", lv.hero.is_on_floor())
	if a.size() > 5:
		for c in lv.get_children():
			if c is StageLighting:
				c._strike_at = 0.0
		await get_tree().create_timer(float(a[5]), false).timeout
	for i in 4: await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a[1])
	get_tree().quit()
