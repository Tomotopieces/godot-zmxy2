class_name SkillShop
extends CanvasLayer
## Skill learning panel (export.shop.SkillControl): active page buys Wukong's five skills with souls,
## passive page levels the five passive skills. Opened from the map (showBuySkill) or in a stage (V / btn_study).

const PASSIVE := ["instrmc/pskill1", "instrmc/pskill2", "instrmc/pskill3", "instrmc/pskill4", "instrmc/pskill5"]
const PASSIVE_FRAME := 3              ## instrmc frame of the passive page
const PASSIVE_NAME := {"hp": "热血", "mp": "魔泉", "crit": "狂暴", "hp_regen": "光之永恒", "mp_regen": "月之辉煌"}
const STAT_FORMAT := {"hp": "生命上限 +%d", "mp": "魔法上限 +%d", "crit": "暴击 +%d%%", "hp_regen": "每秒回血 +%d", "mp_regen": "每秒回魔 +%d"}

var _ui: UiLayout
var _active: Array[String] = []   ## the five skill icons of this hero's page
var _active_hits: Array[Control] = []
var _passive_rows: Array[UiLayout] = []

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	var paused_before := get_tree().paused
	get_tree().paused = true
	tree_exiting.connect(func(): get_tree().paused = paused_before)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.size = Layers.VIEW
	add_child(dim)
	# the panel sits inside BuySkill (background, character tabs, back button)
	var back := UiLayout.create("buy_skill")
	var role := GameState.hero_data.role_index
	for i in 3:
		back.set_visible_piece("player%d" % (i + 1), i == role)
	back.button_pressed.connect(func(b): if b == "btnback": UiFade.close(self))
	add_child(back)
	_ui = UiLayout.create("skill_control")
	add_child(_ui)
	for i in 5:
		_active.append("instrmc/skill%d@%d" % [i + 1, role])
		_active_hits.append(_ui.make_clickable(_active[i]))
	# passive rows: the nested PassiveSkill clip keeps the row's frame; a passive_skill row on top provides the name,
	# the texts and the upgrade button
	for i in PASSIVE.size():
		_ui.show_frame(PASSIVE[i], i)
		var row := UiLayout.create("passive_skill")
		row.hide_unnamed()
		row.set_text("name", PASSIVE_NAME[GameState.hero_data.learn_passive[i]])
		row.position = _ui.piece_position(PASSIVE[i]) - _ui.piece_position("instrmc")
		row.button_pressed.connect(func(_b): _upgrade(i))
		_ui.get_piece("instrmc").get_child(PASSIVE_FRAME).add_child(row)
		_passive_rows.append(row)
	_ui.button_pressed.connect(_on_button)
	_show_page(false)
	UiFade.fade_in(self)

func _show_page(passive: bool) -> void:
	_ui.show_frame("bgmc", 1 if passive else 0)
	_ui.show_frame("instrmc", PASSIVE_FRAME if passive else GameState.hero_data.role_index)
	for h in _active_hits:
		h.visible = not passive
	_refresh()

func _refresh() -> void:
	_ui.set_text("txtlh", str(GameState.souls))
	for i in _active.size():
		var learned := GameState.has_skill(StringName(GameState.hero_data.learn_active[i]))
		_ui.show_frame(_active[i], 1 if learned else 0)
	for i in _passive_rows.size():
		var row := _passive_rows[i]
		var lv: int = GameState.passives[i]
		var stat := GameState.hero_data.learn_passive[i]
		var fmt: String = STAT_FORMAT[stat]
		var scale := 100.0 if stat == "crit" else 1.0
		row.set_text("curslevel", "%d级" % lv)
		row.set_text("lastvalue", fmt % roundi(GameState.hero_data.passive_value(stat, lv) * scale) if lv > 0 else "-")
		var maxed := lv >= GameState.hero_data.passive_max
		row.set_text("attvalue", "已满级" if maxed else fmt % roundi(GameState.hero_data.passive_value(stat, lv + 1) * scale))
		row.set_text("wantlh", "" if maxed else str(GameState.passive_cost(i)))
		row.set_visible_piece("btn", not maxed)

func _on_button(b: String) -> void:
	match b:
		"activebtn":
			_show_page(false)
		"passivebtn":
			_show_page(true)
	var i := _active.find(b)
	if i >= 0 and GameState.learn(i):
		Snd.ui("SD_xz")
		_refresh()

func _upgrade(i: int) -> void:
	if GameState.upgrade_passive(i):
		Snd.ui("SD_xz")
		_refresh()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") or e.is_action_pressed("open_skills"):
		get_viewport().set_input_as_handled()
		UiFade.close(self)
