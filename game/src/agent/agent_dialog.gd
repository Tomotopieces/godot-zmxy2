class_name AgentDialog
extends CanvasLayer
## 设置 -> AI 接入 (scenes/ui/agent_dialog.tscn): the connection string of zmxy2-remake-mcp. Saving an empty one turns
## the connection off.

var _ui: UiLayout

func _ready() -> void:
	layer = 17
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui = UiLayout.create("agent_dialog")
	add_child(_ui)
	var field: LineEdit = _ui.piece("Url")
	field.text = AgentBridge.url
	_ui.button_pressed.connect(func(b: String):
		if b == "BtnSave":
			AgentBridge.set_url(field.text)
		UiFade.close(self))
	PadFocus.modal(_ui)
	UiFade.fade_in(self)

func _process(_dt: float) -> void:
	_ui.set_text("Status", "已连接" if AgentBridge.connected() else ("等待 MCP 服务…" if AgentBridge.url != "" else "未开启"))

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		UiFade.close(self)
