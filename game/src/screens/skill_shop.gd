class_name SkillShop
extends CanvasLayer
## Skill learning panel (export.shop.SkillControl): the active page (ActiveSkillPanel) buys the hero's five skills with
## souls, the passive page (PassiveSkillPanel) levels the five passive skills. Both are tables in the scene: one
## column per field, row i = skill i. Opened from the map (showBuySkill) or in a stage (V / btn_study).

const HEROES := ["Wukong", "Tangseng", "Bajie"]   ## ActiveSkillPanel/Skills child per role_index
const PASSIVE_NAME := {"hp": "热血", "mp": "魔泉", "crit": "狂暴", "hp_regen": "光之永恒", "mp_regen": "月之辉煌"}
const STAT_FORMAT := {"hp": "生命上限 +%d", "mp": "魔法上限 +%d", "crit": "暴击 +%d%%", "hp_regen": "每秒回血 +%d", "mp_regen": "每秒回魔 +%d"}

var _ui: UiLayout
var _active: Array[Button] = []   ## the five skill icons of this hero's table (normal = not learned, disabled = learned)
var _table: Node2D               ## this hero's table (names, icons, keys, descriptions)
var _passive: Node2D             ## PassiveSkillPanel/Skills
var _upgrades: Array[Button] = []

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
	_table = _ui.get_node("ActiveSkillPanel/Skills/" + HEROES[role])
	var costs := _ui.get_node("ActiveSkillPanel/Requirements")
	for i in 5:
		var b: Button = _table.get_node("Icons/Skill%d/Button" % (i + 1))
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_learn.bind(i))
		PadNav.mark(b)
		_active.append(b)
		(costs.get_child(i) as Label).text = str(GameState.learn_cost(i))
	_show_keys(false)
	_passive = _ui.get_node("PassiveSkillPanel/Skills")
	for i in 5:
		_cell("Names", i).text = PASSIVE_NAME[GameState.hero_data.learn_passive[i]]
		var b: Button = _passive.get_node("Upgrade/Skill%d" % (i + 1))
		b.pressed.connect(_upgrade.bind(i))
		PadNav.mark(b)
		_upgrades.append(b)
	_ui.button_pressed.connect(_on_button)
	_show_page(false)
	UiFade.fade_in(self)

func _show_page(passive: bool) -> void:
	_ui.get_node("ActiveSkillPanel").visible = not passive
	_ui.get_node("PassiveSkillPanel").visible = passive
	for i in HEROES.size():
		_table.get_parent().get_child(i).visible = i == GameState.hero_data.role_index
	_refresh()

func _refresh() -> void:
	_ui.set_text("txtlh", str(GameState.souls))
	for i in _active.size():
		_active[i].disabled = GameState.has_skill(StringName(GameState.hero_data.learn_active[i]))
	for i in 5:
		var lv: int = GameState.passives[i]
		var stat := GameState.hero_data.learn_passive[i]
		var fmt: String = STAT_FORMAT[stat]
		var scale := 100.0 if stat == "crit" else 1.0
		var maxed := lv >= GameState.hero_data.passive_max
		_cell("Levels", i).text = "%d级" % lv
		_cell("Effects", i).text = fmt % roundi(GameState.hero_data.passive_value(stat, lv) * scale) if lv > 0 else "-"
		_cell("NextEffects", i).text = "已满级" if maxed else fmt % roundi(GameState.hero_data.passive_value(stat, lv + 1) * scale)
		_cell("Requirements", i).text = "-" if maxed else str(GameState.passive_cost(i))
		_upgrades[i].visible = not maxed

## Row i of a passive-table column.
func _cell(column: String, i: int) -> Label:
	return _passive.get_node("%s/Skill%d" % [column, i + 1])

func _on_button(b: String) -> void:
	match b:
		"activebtn":
			_show_page(false)
		"passivebtn":
			_show_page(true)

func _learn(i: int) -> void:
	if GameState.learn(i):
		Snd.ui("SD_xz")
		_refresh()

## The key column follows the device last used: keyboard keys or pad buttons.
func _show_keys(pad: bool) -> void:
	_table.get_node("KeyboardInput").visible = not pad
	_table.get_node("ControllerInput").visible = pad

func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.5):
		_show_keys(true)
	elif e is InputEventKey or e is InputEventMouseButton:
		_show_keys(false)

func _upgrade(i: int) -> void:
	if GameState.upgrade_passive(i):
		Snd.ui("SD_xz")
		_refresh()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") or e.is_action_pressed("open_skills"):
		get_viewport().set_input_as_handled()
		UiFade.close(self)
