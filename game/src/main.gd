extends Node
## Game root: switches between title, stage map and play screens.

var _screen: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Controls.add_gamepad_defaults()
	get_viewport().size_changed.connect(_update_filter_scale)
	_update_filter_scale()
	if OS.is_debug_build():   # debug aids are not part of exported (release) builds
		add_child(DebugConsole.new())   # ~ lists every item
	show_menu()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		Controls.toggle_fullscreen()

## Filter sizes (blur / glow) are authored in game pixels; the shader needs screen pixels.
func _update_filter_scale() -> void:
	RenderingServer.global_shader_parameter_set(&"flash_px_scale", get_viewport().get_final_transform().get_scale().x)

func _swap(n: Node) -> void:
	if _screen:
		_screen.queue_free()
	get_tree().paused = false
	_screen = n
	add_child(n)

func show_menu() -> void:
	var m := MainMenu.new()
	m.new_game.connect(func():
		GameState.new_game()
		_after_new_game())
	m.continued.connect(show_map)
	_swap(m)

## New game: the opening comic once, then the map.
func _after_new_game() -> void:
	if GameState.opening_seen:
		show_map()
		return
	GameState.opening_seen = true
	var c := Cartoon.create("开场")
	c.finished.connect(show_map)
	_swap(c)

func show_map() -> void:
	var m := StageMap.new()
	m.play.connect(start_stage)
	m.to_menu.connect(show_menu)
	_swap(m)

func start_stage(s: Vector2i) -> void:
	var p := PlayScreen.create(s)
	p.to_map.connect(show_map)
	p.to_menu.connect(show_menu)
	p.play.connect(start_stage)
	_swap(p)
