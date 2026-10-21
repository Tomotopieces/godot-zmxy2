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
	for part in ["Picture", "Intro"]:   # the treasure's own picture and introduction
		for c in _ui.piece(part).get_children():
			c.visible = c.name == TREASURE_NODES.get(d.display_name, "")
	_refresh()
	UiFade.fade_in(self)

func _item() -> Item:
	return GameState.worn[&"treasure"]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") or e.is_action_pressed("open_treasure"):
		get_viewport().set_input_as_handled()
		UiFade.close(self)

func _on_button(b: String) -> void:
	match b:
		"BtnClose":
			UiFade.close(self)
		"BtnShengJi":
			var it := _item()
			var cost := Forge.upgrade_cost(it)
			if cost > 0 and GameState.souls >= cost:
				GameState.souls -= cost
				Forge.upgrade(it)
				GameState.equipment_changed.emit()
				GameState.profile_changed.emit()
				_refresh()

## The treasures' nodes in Picture / Intro.
const TREASURE_NODES := {"天煞古剑": "TianShaGuJian", "罗刹妖伞": "LuoShaYaoSan", "血海魔童": "XueHaiMoTong", "地煞葫芦": "DiShaHuLu",
	"白霜镜": "BaiShuangJing", "五毒兽": "WuDuShou"}
## 五毒兽 passive: stat -> [icon node, text] (MyEquipObj.getwhichpskill); the stat's own value follows the text
const PASSIVES := {"crit": ["KuangBao", "狂暴:暴击率增加"], "lifesteal": ["ShiXue", "嗜血:吸血增加"], "mdef": ["WanGu", "顽固:魔抗增加"],
	"hp_regen": ["YongHeng", "永恒:回血增加"], "mp_regen": ["HuiHuang", "辉煌:回蓝增加"]}
## 五毒兽 spell: [kind, upgraded] -> [icon node, text] (MyEquipObj.getwhichskill)
const SPELLS := {[0, false]: ["ChuJiLeiZhou", "对前方怪物造成雷电伤害"], [0, true]: ["GaoJiLeiZhou", "对全屏怪物造成雷电伤害"],
	[1, false]: ["ChuJiHuoZhou", "对前方怪物造成火焰伤害"], [1, true]: ["GaoJiHuoZhou", "对全屏怪物造成火焰伤害"]}

func _refresh() -> void:
	var it := _item()
	var d := GameState.item_data(it)
	var cost := Forge.upgrade_cost(it)
	_ui.set_text("TreasureName", d.display_name)
	_stat("StatFbdj", str(int(it.lv)))
	_stat("StatFbczl", "%.1f" % it.growth)
	_stat("StatFbwx", Forge.element_text(it))
	var st := it.stats
	_stat("StatFbatk", str(int(st.get("atk", 0))))
	_stat("StatFbdef", str(int(st.get("def", 0))))
	_stat("StatFbhx", str(int(st.get("hp", 0))))
	_stat("StatFbhl", str(int(st.get("mp", 0))))
	_stat("CurrencyFblh", "%d/%s" % [GameState.souls, str(cost) if cost > 0 else "满级"])
	(_ui.piece("CurrencyFblhProgress") as Range).value = 1.0 if cost == 0 else float(GameState.souls) / (cost + 1)
	if it.id == "wds":
		# the spell and the passive each have an icon and a text under it
		var spell: Array = SPELLS[[int(it.spell), it.strong]]
		_show_only(_ui.piece("SpellIcon"), spell[0])
		_ui.set_text("SpellText", spell[1] + " ")
		for k in PASSIVES:
			if st.has(k):
				var v: float = st[k]
				var p: Array = PASSIVES[k]
				_show_only(_ui.piece("PassiveIcon"), p[0])
				_ui.set_text("PassiveText", "%s%s " % [p[1], ("%s%%" % String.num(snappedf(v * 100.0, 0.01))) if v < 1.0 else str(int(v))])
func _stat(row: String, value: String) -> void:
	_ui.piece(row).set_value(value)

static func _show_only(parent: Node, child: String) -> void:
	for c in parent.get_children():
		c.visible = c.name == child
