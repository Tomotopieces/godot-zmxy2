class_name StageMap
extends CanvasLayer
## Stage select map (export.SelectPLace). Main path stages unlock in order; the furthest unlocked one pulses a purple
## glow. A stage is a Button with its Picture and the larger HoverPicture shown while hovered. 牛魔谷 = 6-1 and
## 螺旋地狱 = 10-1 have no unlock check.

signal play(stage: Vector2i)
signal to_menu

const MAIN_STAGES := {"Stage1Level1": Vector2i(1, 1), "Stage1Level2": Vector2i(1, 2), "Stage1Level3": Vector2i(1, 3),
	"Stage2Level1": Vector2i(2, 1), "Stage2Level2": Vector2i(2, 2), "Stage2Level3": Vector2i(2, 3), "Stage3Level1": Vector2i(3, 1),
	"Stage3Level2": Vector2i(3, 2), "Stage3Level3": Vector2i(3, 3), "Stage4Level1": Vector2i(4, 1)}
const SIDE_STAGES := {"NiuMoGu": Vector2i(6, 1), "LuoXuanDiYu": Vector2i(10, 1)}
## the next stage's pulse: GlowFilter 0x9900CC, blur 0 -> 12 -> 0, strength 0 -> 1.82, over 19 frames
const NEXT_GLOW_COLOR := Color8(153, 0, 204)
const NEXT_GLOW_BLUR := Vector2(0.0, 12.0)
const NEXT_GLOW_STRENGTH := Vector2(0.0, 1.82)
const NEXT_GLOW_HALF := 9.0 / 24.0
var _ui: UiLayout
var _popup: Node

func _ready() -> void:
	_ui = get_node_or_null("Map") as UiLayout   # the layout instanced in stage_map.tscn
	if _ui == null:
		_ui = UiLayout.create("stage_map")
		add_child(_ui)
	for p in MAIN_STAGES:
		var b: Button = _ui.piece(p)
		if MAIN_STAGES[p] == GameState.progress:
			_ui.glow_pulse(b.get_node("Picture"), NEXT_GLOW_COLOR, NEXT_GLOW_BLUR, NEXT_GLOW_STRENGTH, NEXT_GLOW_HALF)
		b.disabled = not GameState.is_unlocked(MAIN_STAGES[p])
		_hover_art(b)
	for p in SIDE_STAGES:
		_hover_art(_ui.piece(p))
	_ui.button_pressed.connect(_on_button)
	Snd.music("begin")

## The bigger picture while hovered (a locked stage has none).
static func _hover_art(b: Button) -> void:
	var show := func(on: bool) -> void:
		b.get_node("HoverPicture").visible = on and not b.disabled
		b.get_node("Picture").visible = not b.get_node("HoverPicture").visible
	b.mouse_entered.connect(show.bind(true))
	b.mouse_exited.connect(show.bind(false))
	b.focus_entered.connect(show.bind(true))   # the pad's focus too
	b.focus_exited.connect(show.bind(false))
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW if b.disabled else Control.CURSOR_POINTING_HAND

func _on_button(b: String) -> void:
	if _popup:
		return
	if MAIN_STAGES.has(b):
		play.emit(MAIN_STAGES[b])
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
		"BtnBack":
			to_menu.emit()
		"BtnSave":
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
		"BtnSkills":
			_open(SkillShop.new())
		"BtnForge":
			_open(ForgeScreen.new())
		"BtnShop":
			_open(ShopScreen.new())
		"BtnActivity":
			var a := ActivityPanel.new()
			a.play.connect(func(s: Vector2i): play.emit(s))
			_open(a)

func _saved(slot: int) -> void:
	Toast.show_on(self, "存档成功")

func _open(n: Node) -> void:
	_popup = n
	n.tree_exited.connect(func(): _popup = null)
	add_child(n)
