class_name SutraPanel
extends CanvasLayer
## 法宝升级 (export.strength.SutraInterface), from the HUD 法宝 button: shows the worn treasure and levels it up
## for souls (level L -> L+1 costs L^2 x 1000, up to level 10). Pauses the game while open.

var _ui: UiLayout
var _spell: Label
var _passive: Label

static func open_on(parent: Node) -> SutraPanel:
	if GameState.worn[&"treasure"] == null:
		Toast.show_on(parent, "请先装备法宝")
		return null
	var s := SutraPanel.new()
	parent.add_child(s)
	return s

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	var paused_before := get_tree().paused
	get_tree().paused = true
	tree_exiting.connect(func(): get_tree().paused = paused_before)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = Layers.VIEW
	add_child(dim)
	_ui = UiLayout.create("sutra")
	_ui.button_pressed.connect(_on_button)
	add_child(_ui)
	var d := GameState.item_data(_item())
	_ui.show_frame("showmc", d.display_name)
	_ui.show_frame("introducemc", d.display_name)
	# 五毒兽: its spell and passive under their icons (introducemc txt1 / txt2 in the original)
	_spell = _note(SPELL_TEXT_POS)
	_passive = _note(PASSIVE_TEXT_POS)
	_refresh()

const SPELL_TEXT_POS := Vector2(502, 240)
const PASSIVE_TEXT_POS := Vector2(502, 370)

func _note(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.2, 0.1, 0.05))
	add_child(l)
	return l

func _item() -> Item:
	return GameState.worn[&"treasure"]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()

func _on_button(b: String) -> void:
	match b:
		"btn_close":
			queue_free()
		"btn_sj":
			var it := _item()
			var cost := Forge.upgrade_cost(it)
			if cost > 0 and GameState.souls >= cost:
				GameState.souls -= cost
				Forge.upgrade(it)
				GameState.equipment_changed.emit()
				GameState.profile_changed.emit()
				_refresh()

const PASSIVE_NAMES := {"crit": ["狂暴", "暴击率"], "lifesteal": ["嗜血", "吸血"], "mdef": ["顽固", "魔抗"],
	"hp_regen": ["永恒", "回血"], "mp_regen": ["辉煌", "回蓝"]}

func _refresh() -> void:
	var it := _item()
	var d := GameState.item_data(it)
	var cost := Forge.upgrade_cost(it)
	_ui.set_text("txt_fbname", d.display_name)
	_ui.set_text("txt_fbdj", str(int(it.lv)))
	_ui.set_text("txt_fbczl", "%.1f" % it.growth)
	_ui.set_text("txt_fbwx", Forge.element_text(it))
	var st := it.stats
	_ui.set_text("txt_fbatk", str(int(st.get("atk", 0))))
	_ui.set_text("txt_fbdef", str(int(st.get("def", 0))))
	_ui.set_text("txt_fbhx", str(int(st.get("hp", 0))))
	_ui.set_text("txt_fbhl", str(int(st.get("mp", 0))))
	_ui.set_text("txt_fblh", "%d/%s" % [GameState.souls, str(cost) if cost > 0 else "满级"])
	_ui.set_bar("lhmc", 1.0 if cost == 0 else float(GameState.souls) / (cost + 1))
	_spell.text = ""
	_passive.text = ""
	if it.id == "wds":
		var strong := "全屏" if it.strong else "初级"
		_spell.text = "%s%s咒" % [strong, "雷" if it.spell == 0 else "火"]
	for k in PASSIVE_NAMES:
		if it.id == "wds" and st.has(k):
			var v: float = st[k]
			_passive.text = "%s:%s增加%s" % [PASSIVE_NAMES[k][0], PASSIVE_NAMES[k][1], ("%d%%" % roundi(v * 100)) if v < 1.0 else str(int(v))]
