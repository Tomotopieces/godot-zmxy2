class_name StageMap
extends CanvasLayer
## Stage select map (export.SelectPLace). Main path stages s1_1 .. s4_1 unlock in order; frame 1 marks the
## furthest unlocked stage (a 19-frame clip pulsing a purple glow), frame 2 is hover. btnnmg = 6-1 and
## lxdy = 10-1 have no unlock check.

signal play(stage: Vector2i)
signal to_menu

const MAIN_STAGES := ["s1_1", "s1_2", "s1_3", "s2_1", "s2_2", "s2_3", "s3_1", "s3_2", "s3_3", "s4_1"]
const SIDE_STAGES := {"btnnmg": Vector2i(6, 1), "lxdy": Vector2i(10, 1)}
const HIDDEN := ["s4_2", "s4_3", "arena", "submitbtn"]
## the next stage's pulse: GlowFilter 0x9900CC, blur 0 -> 12 -> 0, strength 0 -> 1.82, over 19 frames
const NEXT_GLOW_COLOR := Color8(153, 0, 204)
const NEXT_GLOW_BLUR := Vector2(0.0, 12.0)
const NEXT_GLOW_STRENGTH := Vector2(0.0, 1.82)
const NEXT_GLOW_HALF := 9.0 / 24.0
## bottom-right buttons; with 提交分数 gone the others close up to the right
const BOTTOM_ROW := ["scgm", "savebtn", "ldl", "showBuySkill"]
const BOTTOM_SHIFT_FROM := "submitbtn"   ## the first hidden slot: the row moves right by one slot
const BOTTOM_SHIFT_TO := "btnback"

var _ui: UiLayout
var _popup: Node

func _ready() -> void:
	_ui = UiLayout.create("stage_map")
	add_child(_ui)
	for p in HIDDEN:
		_ui.set_visible_piece(p, false)
	for p in MAIN_STAGES:
		var s := _stage_of(p)
		var current: bool = s == GameState.progress
		_ui.show_frame(p, 1 if current else 0)
		if current:
			_ui.glow_pulse(_ui.get_piece(p).get_child(1), NEXT_GLOW_COLOR, NEXT_GLOW_BLUR, NEXT_GLOW_STRENGTH, NEXT_GLOW_HALF)
		if GameState.is_unlocked(s):
			_ui.make_clickable(p, 2, 1 if current else 0)
	for p in SIDE_STAGES:
		_ui.make_clickable(p, 2, 0)
	_close_up_buttons()
	_ui.set_visible_piece("saveInterval", false)   # the original counted down 30 s between saves (a web-game guard)
	_ui.button_pressed.connect(_on_button)
	Snd.music("begin")

func _close_up_buttons() -> void:
	var slot: float = (_ui.get_piece(BOTTOM_SHIFT_TO).position.x - _ui.get_piece(BOTTOM_SHIFT_FROM).position.x) / 2.0
	var shift := slot
	for p in BOTTOM_ROW:
		_ui.get_piece(p).position.x += shift

static func _stage_of(piece: String) -> Vector2i:
	return Vector2i(int(piece[1]), int(piece[3]))

func _on_button(b: String) -> void:
	if _popup:
		return
	if b in MAIN_STAGES:
		play.emit(_stage_of(b))
	elif SIDE_STAGES.has(b):
		var to: Vector2i = SIDE_STAGES[b]
		if to.x == 6 and not GameState.hhe_seen:
			# first trip to 红孩儿: its comic page, then the stage
			GameState.hhe_seen = true
			var c := Cartoon.create("红孩儿副本")
			c.finished.connect(func(): play.emit(to))
			_popup = c
			add_child(c)
		else:
			play.emit(to)
	match b:
		"btnback":
			to_menu.emit()
		"savebtn":
			if GameState.slot >= 0:
				# a game that already has a slot saves straight into it
				GameState.save_to(GameState.slot)
				_saved(GameState.slot)
			else:
				var p := SavePanel.create(SavePanel.Mode.SAVE)
				p.done.connect(func(slot):
					_popup = null
					if slot >= 0:
						_saved(slot))
				_popup = p
				add_child(p)
		"showBuySkill":
			_open(SkillShop.new())
		"ldl":
			_open(ForgeScreen.new())
		"scgm":
			_open(ShopScreen.new())
		"huodongbtn":
			var a := ActivityPanel.new()
			a.play.connect(func(s: Vector2i): play.emit(s))
			_open(a)

func _saved(slot: int) -> void:
	Toast.show_on(self, "存档成功")

func _open(n: Node) -> void:
	_popup = n
	n.tree_exited.connect(func(): _popup = null)
	add_child(n)
