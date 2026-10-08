extends Node
## scratch: clear fade

var _out := "C:/Users/ADMINI~1/AppData/Local/Temp/shots"

func _ready() -> void:
	GameState.new_game()
	var main: PlayScreen = PlayScreen.create(Vector2i(1, 1))
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	main.level.open_door()
	main.level.hero.global_position = main.level.door_rect.get_center()
	main.level.view_x = main.level.door_rect.position.x - 400
	main.level.hero.reset_physics_interpolation()
	await get_tree().create_timer(0.3).timeout
	main.level.stage_cleared.emit()
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(_out + "/fade_mid.png")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(_out + "/fade_done.png")
	get_tree().quit()
