class_name HelpPanel
extends CanvasLayer
## 游戏帮助: the controls and every hero's skill keys (scenes/ui/help.tscn). Opened from the title and the pause menu;
## the back button, Esc or the pad's B closes it.

func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui := UiLayout.create("help")
	PadNav.modal(ui)
	ui.button_pressed.connect(func(b): if b == "btnback": UiFade.close(self))
	add_child(ui)
	UiFade.fade_in(self)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		UiFade.close(self)
