class_name PauseMenu
extends Control
## 设置, a page of the TabMenu (scenes/ui/set_menu.tscn): continue, sound / screen shake / pad rumble switches, back to
## map, help, AI 接入 (the agent connection, AgentDialog), back to the title.

signal to_map
signal to_menu

var in_stage := true   ## false on the map: no 继续游戏 / 返回地图
var _ui: UiLayout

func _ready() -> void:
	_ui = UiLayout.create("set_menu")
	add_child(_ui)
	for b in ["BtnContinue", "BtnBackToMap"]:
		_ui.piece(b).visible = in_stage
	_sync()
	Snd.volume_changed.connect(func(_v, _m): _sync())   # M key while the menu is open
	_ui.button_pressed.connect(_on_button)

func _on_button(b: String) -> void:
	match b:
		"BtnContinue": TabMenu.close_of(self)
		"BtnBackToMap": to_map.emit()
		"BtnBackToTitle": to_menu.emit()
		"BtnHelp": add_child(HelpPanel.new())
		"BtnAgent": add_child(AgentDialog.new())
		"BtnGameSound": Snd.set_muted(not Snd.muted)
		"BtnScreenShake":
			Feel.screen_shake = not Feel.screen_shake
			Feel.save_settings()
		"BtnControllerShake":
			Feel.pad_rumble = not Feel.pad_rumble
			Feel.save_settings()
			if Feel.pad_rumble:
				Feel.rumble(0.5, 0.15)
	_sync()

## The three switches show their state in their own text.
func _sync() -> void:
	_switch("BtnGameSound", "游戏声音", not Snd.muted)
	_switch("BtnScreenShake", "画面震动", Feel.screen_shake)
	_switch("BtnControllerShake", "手柄震动", Feel.pad_rumble)
	_ui.set_text("BtnAgent", "AI 接入：" + ("已连接" if AgentBridge.connected() else ("等待连接" if AgentBridge.url != "" else "关")))

func _switch(button: String, caption: String, on: bool) -> void:
	_ui.set_text(button, "%s：%s" % [caption, "开" if on else "关"])

