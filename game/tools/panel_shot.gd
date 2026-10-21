extends Node
## Screenshots the real bag, treasure and shop panels (the ones the game opens) into <out_dir>:
##   godot --path game --position 6000,6000 res://tools/panel_shot.tscn -- <out_dir> [role]
## A scene (not -s) so the autoloads (GameState, Snd) and the default theme exist, exactly as in the game.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	GameState.new_game(args[1] if args.size() > 1 else "wukong")   # [role]
	GameState.souls = 300
	GameState.exp = int(GameState.exp_to_next() * 0.6)
	var main: PlayScreen = PlayScreen.create(Vector2i(1, 1))
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	# a worn treasure, the way the console / tests hand one out (the 法宝 tab needs one)
	var it := GameState.make_item("dshl")
	GameState.add_to_bag(it)
	GameState.wear(GameState.bag.find(it))
	main.open_menu(&"bag")
	await get_tree().create_timer(0.5).timeout
	await _shot(out + "/B_backpack.png")
	main._menu.show_tab(&"treasure")
	await get_tree().create_timer(0.5).timeout
	await _shot(out + "/B_sutra.png")
	main.queue_free()
	var shop := ShopScreen.new()
	add_child(shop)
	await get_tree().create_timer(0.5).timeout
	await _shot(out + "/B_shop.png")
	await get_tree().create_timer(0.35).timeout
	await _shot(out + "/B_shop2.png")
	get_tree().quit()

func _shot(path: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
