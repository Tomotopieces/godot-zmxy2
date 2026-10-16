extends Node
## Game root: switches between title, stage map and play screens.

const TITLE := preload("res://scenes/screens/title_screen.tscn")
const STAGE_MAP := preload("res://scenes/screens/stage_map.tscn")

var _screen: Node
var _title_in_scene := true   ## main.tscn holds a title already (so opening it in the editor shows the title screen)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Controls.add_gamepad_defaults()
	add_child(PadNav.new())
	if OS.is_debug_build():   # debug aids are not part of exported (release) builds
		add_child(DebugConsole.new())   # ~ lists every item
	show_menu()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		Controls.toggle_fullscreen()
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F:
		GameState.strip_trick = not GameState.strip_trick
		if Level.current:
			Level.current.toast("脱衣回蓝：" + ("开" if GameState.strip_trick else "关"))

func _swap(n: Node) -> void:
	if _screen:
		_screen.queue_free()
	get_tree().paused = false
	_screen = n
	add_child(n)

func show_menu() -> void:
	var m: MainMenu
	if _title_in_scene:
		# the TitleScreen main.tscn already holds: adopted, not added again
		_title_in_scene = false
		m = $TitleScreen
		_screen = m
	else:
		m = TITLE.instantiate()
		_swap(m)
	m.new_game.connect(show_select_role)
	m.continued.connect(show_map)

## New game, step 1: choose the hero.
func show_select_role() -> void:
	var s := SelectRole.new()
	s.chosen.connect(func(role: String):
		GameState.new_game(role)
		_after_new_game())
	s.cancelled.connect(show_menu)
	_swap(s)

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
	var m: StageMap = STAGE_MAP.instantiate()
	m.play.connect(start_stage)
	m.to_menu.connect(show_menu)
	_swap(m)

func start_stage(s: Vector2i) -> void:
	var p := PlayScreen.create(s)
	p.to_map.connect(show_map)
	p.to_menu.connect(show_menu)
	p.play.connect(start_stage)
	_swap(p)
