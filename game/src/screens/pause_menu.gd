class_name PauseMenu
extends CanvasLayer
## In-stage menu (export.setmenu.SetMenu): continue, back to map, back to main menu, help, sound on / off.
## Pauses the game while open.

signal closed
signal to_map
signal to_menu

var _ui: UiLayout
var _help: Node

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

func _on_button(b: String) -> void:
	match b:
		"btn_x", "btn_continue": close()
		"btn_back_selectmap": to_map.emit()
		"btn_back_menu": to_menu.emit()
		"btn_help": _show_help()
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

func _show_help() -> void:
	if _help:
		return
	var h := UiLayout.create("help")
	_help = h
	h.button_pressed.connect(func(b): if b == "btnback":
		h.queue_free()
		_help = null)
	add_child(h)

func close() -> void:
	get_tree().paused = false
	closed.emit()
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
