class_name SutraPanel
extends CanvasLayer
## 法宝升级 (export.strength.SutraInterface), from the HUD 法宝 button: shows the worn treasure and levels it up
## for souls (level L -> L+1 costs L^2 x 1000, up to level 10). Pauses the game while open.

var _ui: UiLayout

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
	_refresh()
	UiFade.fade_in(self)

func _item() -> Item:
	return GameState.worn[&"treasure"]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		UiFade.close(self)

func _on_button(b: String) -> void:
	match b:
		"btn_close":
			UiFade.close(self)
		"btn_sj":
			var it := _item()
			var cost := Forge.upgrade_cost(it)
			if cost > 0 and GameState.souls >= cost:
				GameState.souls -= cost
				Forge.upgrade(it)
				GameState.equipment_changed.emit()
				GameState.profile_changed.emit()
				_refresh()

## 五毒兽 passive: stat -> [icon (clip label), text] (MyEquipObj.getwhichpskill); the stat's own value follows the text
const PASSIVES := {"crit": ["狂暴", "狂暴:暴击率增加"], "lifesteal": ["嗜血", "嗜血:吸血增加"], "mdef": ["顽固", "顽固:魔抗增加"],
	"hp_regen": ["永恒", "永恒:回血增加"], "mp_regen": ["辉煌", "辉煌:回蓝增加"]}
## 五毒兽 spell: [kind, upgraded] -> [icon (clip label), text] (MyEquipObj.getwhichskill)
const SPELLS := {[0, false]: ["初级雷咒", "对前方怪物造成雷电伤害"], [0, true]: ["高级雷咒", "对全屏怪物造成雷电伤害"],
	[1, false]: ["初级火咒", "对前方怪物造成火焰伤害"], [1, true]: ["高级火咒", "对全屏怪物造成火焰伤害"]}

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
	if it.id == "wds":
		# the spell and the passive each have an icon clip and a text under it (introducemc skill1 / txt1, skill2 / txt2)
		var spell: Array = SPELLS[[int(it.spell), it.strong]]
		_ui.show_frame("introducemc/skill1", spell[0])
		_ui.set_inner_text("introducemc", "txt1", spell[1] + " ")
		for k in PASSIVES:
			if st.has(k):
				var v: float = st[k]
				var p: Array = PASSIVES[k]
				_ui.show_frame("introducemc/skill2", p[0])
				_ui.set_inner_text("introducemc", "txt2", "%s%s " % [p[1], ("%s%%" % String.num(snappedf(v * 100.0, 0.01))) if v < 1.0 else str(int(v))])
