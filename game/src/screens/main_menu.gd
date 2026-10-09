class_name MainMenu
extends CanvasLayer
## Title screen (export.GameMenu): new game, continue (save slots), help, about, quit.

signal new_game
signal continued

## platform / 2P buttons of the original that have no use here
const HIDDEN := ["simpleGame", "doubleGame", "backbtn", "btn_solution", "btn_forum", "btnCadpa", "btnGoBack"]

var _ui: UiLayout
var _popup: Node

func _ready() -> void:
	_ui = UiLayout.create("game_menu")
	add_child(_ui)
	for p in HIDDEN:
		_ui.set_visible_piece(p, false)
	_ui.set_text("txt_version", "V2.4")
	_ui.button_pressed.connect(_on_button)
	Snd.music("begin")

func _on_button(b: String) -> void:
	if _popup:
		return
	if b in ["newGame", "continueGame"]:
		Snd.sfx("SD_xz")
	match b:
		"newGame":
			new_game.emit()
		"continueGame":
			var p := SavePanel.create(SavePanel.Mode.LOAD)
			p.done.connect(func(slot):
				_popup = null
				if slot >= 0:
					continued.emit())
			_popup = p
			add_child(p)
		"gameHelp":
			_show_panel("help")
		"aboutUs":
			_show_panel("about")
		"btnquit":
			get_tree().quit()

func _show_panel(ui_name: String) -> void:
	var h := UiLayout.create(ui_name)
	_popup = h
	h.button_pressed.connect(func(_b):
		h.queue_free()
		_popup = null)
	add_child(h)
