class_name PauseMenu
extends CanvasLayer
## In-stage menu (export.setmenu.SetMenu): continue, back to map, back to main menu, help, sound on / off.
## Pauses the game while open.

signal closed
signal to_map
signal to_menu

var _ui: UiLayout

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.size = Layers.VIEW
	add_child(dim)
	_ui = UiLayout.create("set_menu")
	add_child(_ui)
	_sync_sound()
	Snd.volume_changed.connect(func(_v, _m): _sync_sound())   # M key while the menu is open
	_ui.button_pressed.connect(_on_button)
	_wire_option("Options/ScreenShake", func(): Feel.screen_shake = not Feel.screen_shake, func(): return Feel.screen_shake)
	_wire_option("Options/PadRumble", func(): Feel.pad_rumble = not Feel.pad_rumble, func(): return Feel.pad_rumble)
	UiFade.fade_in(self)

## A switch row of the Options box (scene nodes: a Control with Caption and State labels): a click flips it.
func _wire_option(path: String, flip: Callable, is_on: Callable) -> void:
	var row := _ui.get_node(path) as Control
	var state := row.get_node("State") as Label
	var show := func():
		state.text = "开" if is_on.call() else "关"
		state.modulate = Color.WHITE if is_on.call() else Color(1, 1, 1, 0.5)
	show.call()
	PadNav.mark(row)
	row.mouse_entered.connect(func(): row.modulate = Color(1.2, 1.15, 1.0))
	row.mouse_exited.connect(func(): row.modulate = Color.WHITE)
	row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			flip.call()
			Feel.save_settings()
			show.call()
			Snd.ui()
			if path.ends_with("PadRumble") and Feel.pad_rumble:
				Feel.rumble(0.5, 0.15))

func _on_button(b: String) -> void:
	match b:
		"btn_x", "btn_continue": close()
		"btn_back_selectmap": to_map.emit()
		"btn_back_menu": to_menu.emit()
		"btn_help": add_child(HelpPanel.new())
		"btn_sound_open":
			Snd.set_muted(false)
			_sync_sound()
		"btn_sound_close":
			Snd.set_muted(true)
			_sync_sound()

## Only the button for the other sound state is shown.
func _sync_sound() -> void:
	_ui.set_visible_piece("btn_sound_open", Snd.muted)
	_ui.set_visible_piece("btn_sound_close", not Snd.muted)

func close() -> void:
	get_tree().paused = false
	closed.emit()
	UiFade.close(self)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
