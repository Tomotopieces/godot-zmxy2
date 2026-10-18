class_name MainMenu
extends CanvasLayer
## Title screen (main.tscn's Title node): 新的开始, 继续游戏 (save slots), 游戏帮助, 退出游戏.

signal new_game
signal continued

var _ui: UiLayout
var _popup: Node

func _ready() -> void:
	_ui = $Menu
	_ui.button_pressed.connect(_on_button)
	shown()

## The title comes back to the front (it is kept in main.tscn and only hidden while another screen is up).
func shown() -> void:
	close_popup()
	Snd.music("begin")

## Another screen takes over: a save panel left open on the title goes with it.
func close_popup() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null

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
			var h := HelpPanel.new()
			h.tree_exited.connect(func(): _popup = null)
			_popup = h
			add_child(h)
		"btnquit":
			get_tree().quit()
