class_name Hud
extends CanvasLayer
## Player panel of the original RoleInfo layout: portrait, HP / MP / EXP bars, rage bar, level, skill icons.
## Polls the hero every frame.
## The panel is hand-arranged in scenes/screens/hud.tscn (this script only drives those nodes).

signal open_bag
signal open_menu
signal open_skills
signal open_treasure

@onready var _ui: UiLayout = $RoleInfo
@onready var _buffs: Control = $Buffs
var _buff_rows := {}   ## buff name -> Label

func _ready() -> void:
	for i in 3:   # the hero's portrait
		_ui.piece("Portrait").get_child(i).visible = i == GameState.hero_data.role_index
	_setup_rage_glow()
	_ui.button_pressed.connect(_on_button)
	GameState.buffs_changed.connect(_rebuild_buffs)
	_rebuild_buffs()

## Running item buffs (export.HeroBuff): one row each, small icon + red time left.
const BUFF_ROW := 30.0

static var _buff_icons := {}

static func _buff_icon(name: String) -> Texture2D:
	if not _buff_icons.has(name):
		_buff_icons[name] = load("res://assets/ui/buffs/%s.png" % name)
	return _buff_icons[name]

func _rebuild_buffs() -> void:
	for c in _buffs.get_children():
		c.queue_free()
	_buff_rows.clear()
	var defs: Dictionary = EquipmentCatalog.get_catalog().buffs
	var row := 0
	for b in GameState.buffs:
		var icon := Sprite2D.new()
		icon.centered = false
		icon.texture = _buff_icon(defs[b].icon)
		icon.scale = Vector2.ONE * float(defs[b].icon_scale)
		icon.position = Vector2(30, row * BUFF_ROW)
		_buffs.add_child(icon)
		var l := Label.new()
		l.position = Vector2(60, -3 + row * BUFF_ROW)
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color.RED)
		_buffs.add_child(l)
		_buff_rows[b] = l
		row += 1

func _update_buffs() -> void:
	for b in _buff_rows:
		var t := int(GameState.buffs.get(b, 0.0))
		_buff_rows[b].text = "%d:%d:%d" % [t / 3600, t / 60 % 60, t % 60]

## The lit 无双 logo (RageLogo/On) is a 19-frame clip pulsing a yellow glow: blur 5 -> 33 -> 5,
## strength 1 -> 3.24 -> 1. Rebuilt as a filter group with a looping tween.
const RAGE_GLOW_COLOR := Color(1.0, 0.8, 0.0)
const RAGE_GLOW_BLUR := Vector2(5.0, 33.0)
const RAGE_GLOW_STRENGTH := Vector2(1.0, 3.24)
const RAGE_GLOW_HALF := 9.0 / 24.0

func _setup_rage_glow() -> void:
	_ui.glow_pulse(_ui.piece("RageLogo").get_node("On"), RAGE_GLOW_COLOR, RAGE_GLOW_BLUR, RAGE_GLOW_STRENGTH, RAGE_GLOW_HALF)

func _on_button(b: String) -> void:
	match b:
		"BtnBag": open_bag.emit()
		"BtnSettings": open_menu.emit()
		"BtnSkills": open_skills.emit()
		"BtnTreasure": open_treasure.emit()

## Notice in the original style (Toast).
func toast(text: String) -> void:
	Toast.show_on(self, text)

## Full-screen 无双 transform animation (WsEffect), centred on screen; plays through the freeze.
func play_rage_transform() -> void:
	var r := Puppet.create("fx_rage_transform")
	r.position = Layers.VIEW / 2.0
	add_child(r)
	r.play(r.actions[0])
	get_tree().create_timer(r.anim.current_animation_length, true).timeout.connect(r.queue_free)

## Boss gauges stack under each other at the top centre ($BossBars sits at x 465, y 50; one bar every 50 px).
var _boss_bars: Array[BossBar] = []

func add_boss_bar(m: Monster) -> void:
	_boss_bars = _boss_bars.filter(func(b): return is_instance_valid(b))
	for old in _boss_bars:   # a boss that changes form hands its bar over to the new body
		if is_instance_valid(old.boss) and old.boss.has_meta(&"handover"):
			old.boss.remove_meta(&"handover")
			old.boss = m
			return
	var b := BossBar.create(m)
	b.position = Vector2(0, 50 * _boss_bars.size())
	$BossBars.add_child(b)
	_boss_bars.append(b)

## Combo counter (export.Batter): shown from 2 hits, fades out over 3.5 s after the last hit.
@onready var _combo: ComboCounter = $Combo

func show_combo(count: int) -> void:
	if count < 2:
		return
	_combo.visible = true
	_combo.show_count(count)

## "GO GO" arrow shown when a camera stop is cleared (StopPoint.destroy).
func play_gogo() -> void:
	var r := Puppet.create("gogo")
	r.position = Vector2(860, 300)
	r.scale = Vector2(0.7, 0.7)
	add_child(r)
	r.action_finished.connect(func(_a): r.queue_free())
	r.play(r.actions[0])

func _process(_dt: float) -> void:
	var lv := Level.current
	if lv == null or not is_instance_valid(lv.hero):
		return
	var h := lv.hero
	_update_buffs()
	_bar("HpBar", float(h.hp) / h.max_hp)
	_bar("MpBar", float(h.mp) / h.max_mp)
	_bar("ExpBar", float(GameState.exp) / GameState.exp_to_next())
	_bar("RageBar", float(h.rage) / h.data.rage_max)
	var lit := h.rage >= h.data.rage_max   # 无双 logo lights up when full
	_ui.piece("RageLogo").get_node("On").visible = lit
	_ui.piece("RageLogo").get_node("Off").visible = not lit
	_ui.set_text("HpText", "%d/%d" % [h.hp, h.max_hp])
	_ui.set_text("MpText", "%d/%d" % [h.mp, h.max_mp])
	_ui.set_text("ExpText", "%d/%d" % [GameState.exp, GameState.exp_to_next()])
	_ui.set_text("LevelText", str(GameState.level))
	# the hero's learned skill i shows its icon (icon 0 = locked; 5 icons per hero)
	var learned := GameState.hero_data.learn_active
	var base := GameState.hero_data.hud_icon_base()
	for i in learned.size():
		(_ui.piece("Skill%d" % (i + 1)) as IconSet).index = base + i if GameState.has_skill(StringName(learned[i])) else 0
func _bar(gauge: String, ratio: float) -> void:
	(_ui.piece(gauge).get_node("Fill") as Range).value = clampf(ratio, 0.0, 1.0)
