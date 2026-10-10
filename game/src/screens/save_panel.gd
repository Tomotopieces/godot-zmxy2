class_name SavePanel
extends CanvasLayer
## Six save slots (export.saveInterface.SaveInter). LOAD picks a slot to continue, SAVE writes the current game.

signal done(slot: int)   ## -1 when closed without choosing

enum Mode { LOAD, SAVE }

const SLOT_PIECES := ["btn_0", "btn_1", "btn_2", "btn_3", "btn_4", "btn_5"]

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
		_ui.set_inner_text(SLOT_PIECES[i], "txt_name", info.get("title", "空存档"))
		_ui.set_inner_text(SLOT_PIECES[i], "txt_time", info.get("datetime", ""))
		if info.has("datetime"):
			# two lines (title over time): the pair, not the title alone, is centred in the slot
			for f in ["txt_name", "txt_time"]:
				for l: Label in _ui.get_piece(SLOT_PIECES[i]).find_children(f, "Label", true, false):
					l.position.y -= 12.0
		_ui.make_clickable(SLOT_PIECES[i], 1, 0)
	_ui.button_pressed.connect(_on_button)

func _on_button(b: String) -> void:
	if b == "btn_x":
		_finish(-1)
		return
	var i := SLOT_PIECES.find(b)
	if i < 0:
		return
	if mode == Mode.LOAD:
		if GameState.slot_info(i).is_empty():
			return
		Snd.sfx("SD_xz")
		GameState.load_from(i)
	else:
		GameState.save_to(i)
	_finish(i)

func _finish(i: int) -> void:
	done.emit(i)
	queue_free()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish(-1)
