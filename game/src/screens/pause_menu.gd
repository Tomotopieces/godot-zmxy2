class_name PauseMenu
extends CanvasLayer
## In-stage menu (scenes/ui/set_menu.tscn): continue, sound / screen shake / pad rumble switches, back to map, help,
## back to the title.
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
	_sync()
	Snd.volume_changed.connect(func(_v, _m): _sync())   # M key while the menu is open
	_ui.button_pressed.connect(_on_button)
	UiFade.fade_in(self)

func _on_button(b: String) -> void:
	match b:
		"btn_x", "btn_continue": close()
		"btn_back_selectmap": to_map.emit()
		"btn_back_menu": to_menu.emit()
		"btn_help": add_child(HelpPanel.new())
		"btn_sound": Snd.set_muted(not Snd.muted)
		"btn_shake":
			Feel.screen_shake = not Feel.screen_shake
			Feel.save_settings()
		"btn_rumble":
			Feel.pad_rumble = not Feel.pad_rumble
			Feel.save_settings()
			if Feel.pad_rumble:
				Feel.rumble(0.5, 0.15)
	_sync()

## The three switches show their state in their own text.
func _sync() -> void:
	_switch("btn_sound", "游戏声音", not Snd.muted)
	_switch("btn_shake", "画面震动", Feel.screen_shake)
	_switch("btn_rumble", "手柄震动", Feel.pad_rumble)

func _switch(piece: String, caption: String, on: bool) -> void:
	var b := _ui.get_piece(piece) as Button
	if b:
		b.text = "%s：%s" % [caption, "开" if on else "关"]

func close() -> void:
	get_tree().paused = false
	closed.emit()
	UiFade.close(self)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
