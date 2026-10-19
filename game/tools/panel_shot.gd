extends Node
## Screenshots the real bag and treasure panels (the ones the game opens) into <out_dir>:
##   godot --path game --position 6000,6000 res://tools/panel_shot.tscn -- <out_dir>
## A scene (not -s) so the autoloads (GameState, Snd) and the default theme exist, exactly as in the game.
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	GameState.new_game("wukong")
	GameState.souls = 300
	GameState.exp = int(GameState.exp_to_next() * 0.6)
	var main: PlayScreen = PlayScreen.create(Vector2i(1, 1))
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	# a worn treasure, the way the console / tests hand one out (SutraPanel.open_on refuses without it)
	var it := GameState.make_item("dshl")
	GameState.add_to_bag(it)
	GameState.wear(GameState.bag.find(it))
	main._open_bag()
	await get_tree().create_timer(0.5).timeout
	await _shot(out + "/B_backpack.png")
	main._bag.close()
	await get_tree().create_timer(0.3).timeout
	main._open_treasure()
	await get_tree().create_timer(0.5).timeout
	await _shot(out + "/B_sutra.png")
	get_tree().quit()

func _shot(path: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
