class_name TabMenu
extends CanvasLayer
## The in-game menu (scenes/ui/tab_menu.tscn): one background with a tab bar on top — 背包 | 技能 | 法宝 | 设置 and 返回 —
## and the chosen tab's page under it (Backpack, SkillShop, SutraPanel, PauseMenu). The pad switches tabs with LT / RT;
## C / V / B open (or, on their own tab, close) a tab, Esc / Start / the pad's B close the menu. 法宝 is greyed out and
## skipped without a worn treasure. Pauses the game while open.

signal to_map
signal to_menu

const TABS: Array[StringName] = [&"bag", &"skill", &"treasure", &"settings"]
const BUTTONS := {&"bag": "BtnBag", &"skill": "BtnSkill", &"treasure": "BtnTreasure", &"settings": "BtnSettings"}
const KEYS := {&"open_bag": &"bag", &"open_skills": &"skill", &"open_treasure": &"treasure"}
const SELECTED := Color(1, 0.6, 0)   ## the open tab's text: the orange of a hovered set_btn
const TRIGGER := 0.6                 ## LT / RT count as pressed past this

var tab: StringName
var page: Control
var _tabs: Array[StringName]
var _ui: UiLayout
var _trigger := {JOY_AXIS_TRIGGER_LEFT: false, JOY_AXIS_TRIGGER_RIGHT: false}

## `tabs`: the tabs this menu has (the map's 技能 button opens one with only 技能).
static func create(first: StringName, tabs: Array[StringName] = TABS) -> TabMenu:
	var m := TabMenu.new()
	m.tab = first
	m._tabs = tabs
	return m

## The menu a page is in: its own close / continue buttons close the whole menu.
static func close_of(n: Node) -> void:
	var p := n.get_parent()
	while p != null and not p is TabMenu:
		p = p.get_parent()
	if p:
		(p as TabMenu).close()

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	var paused_before := get_tree().paused
	get_tree().paused = true
	tree_exiting.connect(func(): get_tree().paused = paused_before)
	_ui = UiLayout.create("tab_menu")
	add_child(_ui)
	for t in TABS:
		var b: Button = _ui.piece(BUTTONS[t])
		b.visible = t in _tabs
		b.focus_mode = Control.FOCUS_NONE   # the pad stays on the page; LT / RT switch tabs
	_ui.piece("BtnBack").focus_mode = Control.FOCUS_NONE
	_ui.button_pressed.connect(_on_button)
	show_tab(tab)
	UiFade.fade_in(self)

func _process(_dt: float) -> void:
	for icon in ["LtIcon", "RtIcon"]:
		_ui.piece(icon).visible = _tabs.size() > 1 and PadFocus.pad_last   # pad hints only while the pad is used

func available(t: StringName) -> bool:
	return t in _tabs and (t != &"treasure" or GameState.worn[&"treasure"] != null)

func show_tab(t: StringName) -> void:
	if page:
		page.queue_free()
	tab = t
	match t:
		&"bag": page = Backpack.new()
		&"skill": page = SkillShop.new()
		&"treasure": page = SutraPanel.new()
		&"settings":
			var p := PauseMenu.new()
			p.to_map.connect(to_map.emit)
			p.to_menu.connect(to_menu.emit)
			page = p
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.piece("Page").add_child(page)
	_sync_tabs()

## The next / previous tab that can be opened.
func step(d: int) -> void:
	var i := _tabs.find(tab)
	for k in _tabs.size() - 1:
		i = posmod(i + d, _tabs.size())
		if available(_tabs[i]):
			Snd.ui()
			show_tab(_tabs[i])
			return

func close() -> void:
	UiFade.close(self)

func _sync_tabs() -> void:
	for t in TABS:
		var b: Button = _ui.piece(BUTTONS[t])
		b.disabled = not available(t)
		b.modulate.a = 1.0 if available(t) else 0.4
		b.tooltip_text = "" if available(t) else "请先装备法宝"
		b.add_theme_color_override(&"font_color", SELECTED if t == tab else Color.WHITE)

func _on_button(b: String) -> void:
	if b == "BtnBack":
		close()
		return
	for t in BUTTONS:
		if BUTTONS[t] == b and t != tab and available(t):
			show_tab(t)

func _input(e: InputEvent) -> void:
	var m := e as InputEventJoypadMotion
	if m == null or not _trigger.has(m.axis):
		return
	var down := m.axis_value > TRIGGER
	if down and not _trigger[m.axis]:
		step(-1 if m.axis == JOY_AXIS_TRIGGER_LEFT else 1)
	_trigger[m.axis] = down
	get_viewport().set_input_as_handled()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
		return
	for action in KEYS:
		if e.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			var t: StringName = KEYS[action]
			if t == tab:
				close()
			elif available(t):
				show_tab(t)
			return
