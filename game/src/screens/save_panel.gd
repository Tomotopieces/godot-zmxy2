class_name SavePanel
extends CanvasLayer
## Six save slots (export.saveInterface.SaveInter). LOAD picks a slot to continue, SAVE writes the current game.

signal done(slot: int)   ## -1 when closed without choosing

enum Mode { LOAD, SAVE }


var mode := Mode.LOAD
var _ui: UiLayout

static func create(m: Mode) -> SavePanel:
	var p := SavePanel.new()
	p.mode = m
	return p

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.size = Layers.VIEW
	add_child(dim)
	_ui = UiLayout.create("save_slots")
	add_child(_ui)
	for i in GameState.SLOTS:
		var info: Dictionary = GameState.slot_info(i)
		var slot := _ui.piece("Slot%d" % (i + 1))
		slot.get_node("Title").text = info.get("title", "空存档")
		slot.get_node("Time").text = info.get("datetime", "")
		if info.has("datetime"):
			# two lines (title over time): the pair, not the title alone, is centred in the slot
			for l in ["Title", "Time"]:
				slot.get_node(l).position.y -= 9.0
	_ui.button_pressed.connect(_on_button)
	UiFade.fade_in(self)

func _on_button(b: String) -> void:
	if b == "BtnClose":
		_finish(-1)
		return
	if not b.begins_with("Slot"):
		return
	var i := int(b.substr(4)) - 1
	if mode == Mode.LOAD:
		if GameState.slot_info(i).is_empty():
			return
		Snd.ui("SD_xz")
		GameState.load_from(i)
	else:
		GameState.save_to(i)
	_finish(i)

func _finish(i: int) -> void:
	done.emit(i)
	UiFade.close(self)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish(-1)
