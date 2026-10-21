class_name SkillShop
extends Control
## Skill learning panel (export.shop.SkillControl): the active page (ActiveSkillPanel) buys the hero's five skills with
## souls, the passive page (PassiveSkillPanel) levels the five passive skills. Both are tables in the scene: one
## column per field, row i = skill i. A page of the TabMenu (the map's 技能 opens one with only this page).

const HEROES := ["Wukong", "Tangseng", "Bajie"]   ## ActiveSkillPanel/Skills child per role_index
const PASSIVE_NAME := {"hp": "热血", "mp": "魔泉", "crit": "狂暴", "hp_regen": "光之永恒", "mp_regen": "月之辉煌"}
const STAT_FORMAT := {"hp": "生命上限 +%d", "mp": "魔法上限 +%d", "crit": "暴击 +%d%%", "hp_regen": "每秒回血 +%d", "mp_regen": "每秒回魔 +%d"}

var _ui: UiLayout
var _active: Array[Button] = []   ## the five skill icons of this hero's table (normal = not learned, disabled = learned)
var _table: Node2D               ## this hero's table (names, icons, keys, descriptions)
var _passive: Node2D             ## PassiveSkillPanel/Skills
var _upgrades: Array[Button] = []

func _ready() -> void:
	var role := GameState.hero_data.role_index
	_ui = UiLayout.create("skill_control")
	add_child(_ui)
	_table = _ui.get_node("ActiveSkillPanel/Skills/" + HEROES[role])
	var costs := _ui.get_node("ActiveSkillPanel/Requirements")
	for i in 5:
		var b: Button = _table.get_node("Icons/Skill%d/Button" % (i + 1))
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_learn.bind(i))
		_active.append(b)
		(costs.get_child(i) as Label).text = str(GameState.learn_cost(i))
	_show_keys(PadFocus.pad_last)
	_passive = _ui.get_node("PassiveSkillPanel/Skills")
	for i in 5:
		_cell("Names", i).text = PASSIVE_NAME[GameState.hero_data.learn_passive[i]]
		var b: Button = _passive.get_node("Upgrade/Skill%d" % (i + 1))
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(_upgrade.bind(i))
		_upgrades.append(b)
	_ui.button_pressed.connect(_on_button)
	_show_page(false)

func _show_page(passive: bool) -> void:
	_ui.get_node("ActiveSkillPanel").visible = not passive
	_ui.get_node("PassiveSkillPanel").visible = passive
	for i in HEROES.size():
		_table.get_parent().get_child(i).visible = i == GameState.hero_data.role_index
	_refresh()

func _refresh() -> void:
	_ui.set_text("Value", str(GameState.souls))
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
		"ActiveButton":
			_show_page(false)
		"PassiveButton":
			_show_page(true)

func _learn(i: int) -> void:
	if GameState.learn(i):
		Snd.ui("SD_xz")
		_refresh()

## The key column follows the device last used: keyboard keys or pad buttons.
func _show_keys(pad: bool) -> void:
	_table.get_node("KeyboardInput").visible = not pad
	_table.get_node("ControllerInput").visible = pad

func _process(_dt: float) -> void:
	_show_keys(PadFocus.pad_last)

func _upgrade(i: int) -> void:
	if GameState.upgrade_passive(i):
		Snd.ui("SD_xz")
		_refresh()
