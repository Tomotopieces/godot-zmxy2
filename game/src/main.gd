extends Node
## Game root: switches between title, stage map and play screens.

const STAGE_MAP := preload("res://scenes/screens/stage_map.tscn")

var _screen: Node
var _fade := ScreenFade.new()
@onready var _title: MainMenu = $Title   ## the title screen lives in main.tscn itself; hidden while another screen is up

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Controls.add_gamepad_defaults()
	add_child(PadNav.new())
	add_child(_fade)
	if OS.is_debug_build():   # debug aids are not part of exported (release) builds
		add_child(DebugConsole.new())   # ~ lists every item
	_title.new_game.connect(func(): _fade.play(show_select_role))
	_title.continued.connect(func(): _fade.play(show_map))

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
	_set_title(false)
	_screen = n
	add_child(n)

func show_menu() -> void:
	if _screen:
		_screen.queue_free()
		_screen = null
	get_tree().paused = false
	_set_title(true)
	_title.shown()

func _set_title(on: bool) -> void:
	if not on:
		_title.close_popup()
	_title.visible = on
	_title.get_node("Menu").visible = on   # (a hidden CanvasLayer still counts its Controls as visible: the pad would find them)
	_title.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

## New game, step 1: choose the hero.
func show_select_role() -> void:
	var s := SelectRole.new()
	s.chosen.connect(func(role: String):
		GameState.new_game(role)
		_fade.play(_after_new_game))
	s.cancelled.connect(show_menu)
	_swap(s)

## New game: the opening comic once, then the map.
func _after_new_game() -> void:
	if GameState.opening_seen:
		show_map()
		return
	GameState.opening_seen = true
	var c := Cartoon.create("开场")
	c.finished.connect(func(): _fade.play(show_map))
	_swap(c)

func show_map() -> void:
	var m: StageMap = STAGE_MAP.instantiate()
	m.play.connect(func(st: Vector2i): _fade.play(start_stage.bind(st)))
	m.to_menu.connect(show_menu)
	_swap(m)

func start_stage(s: Vector2i) -> void:
	var p := PlayScreen.create(s)
	p.to_map.connect(func(): _fade.play(show_map))
	p.to_menu.connect(func(): _fade.play(show_menu))
	p.play.connect(func(st: Vector2i): _fade.play(start_stage.bind(st)))
	_swap(p)
