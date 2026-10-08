class_name Hud
extends CanvasLayer
## Player panel built from the original RoleInfo layout (assets/ui/role_info/ui.json): portrait,
## HP / MP / EXP bars, rage bar, level, skill icons. Polls the hero every frame.

signal open_bag
signal open_menu
signal open_skills
signal open_treasure

var _ui: UiLayout
var _banner: Label
var _buffs: Control
var _buff_rows := {}   ## buff name -> Label

func _ready() -> void:
	_ui = UiLayout.create("role_info")
	add_child(_ui)
	_ui.show_frame("head", 0)
	_setup_rage_glow()
	_ui.button_pressed.connect(_on_button)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position = Vector2(0, 230)
	_banner.size = Vector2(940, 120)
	add_child(_banner)
	_buffs = Control.new()
	_buffs.position = BUFF_POS
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buffs)
	GameState.buffs_changed.connect(_rebuild_buffs)
	_rebuild_buffs()

## Running item buffs (export.HeroBuff): one row each, small icon + red time left.
const BUFF_POS := Vector2(0, 80)
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

## The lit 无双 logo (shows frame 2) is a 19-frame clip pulsing a yellow glow: blur 5 -> 33 -> 5,
## strength 1 -> 3.24 -> 1. Rebuilt as a filter group with a looping tween.
const RAGE_GLOW_COLOR := Color(1.0, 0.8, 0.0)
const RAGE_GLOW_BLUR := Vector2(5.0, 33.0)
const RAGE_GLOW_STRENGTH := Vector2(1.0, 3.24)
const RAGE_GLOW_HALF := 9.0 / 24.0

func _setup_rage_glow() -> void:
	_ui.glow_pulse(_ui.get_piece("shows").get_child(1), RAGE_GLOW_COLOR, RAGE_GLOW_BLUR, RAGE_GLOW_STRENGTH, RAGE_GLOW_HALF)

func _on_button(b: String) -> void:
	match b:
		"btn_bb": open_bag.emit()
		"btn_set": open_menu.emit()
		"btn_study": open_skills.emit()
		"btn_fb": open_treasure.emit()

func banner(text: String) -> void:
	_banner.text = text

## Notice in the original style (Toast).
func toast(text: String) -> void:
	Toast.show_on(self, text)

## Full-screen 无双 transform animation (WsEffect), centred on screen; plays through the freeze.
func play_rage_transform() -> void:
	var r := Rig.create("fx_rage_transform")
	r.position = Layers.VIEW / 2.0
	add_child(r)
	r.play(r.actions[0])
	get_tree().create_timer(r.anim.current_animation_length, true).timeout.connect(r.queue_free)

## Boss gauges stack under each other at the top centre (x 465, y 50 + 50 per bar).
var _boss_bars: Array[BossBar] = []

func add_boss_bar(m: Monster) -> void:
	_boss_bars = _boss_bars.filter(func(b): return is_instance_valid(b))
	var b := BossBar.create(m)
	b.position = Vector2(465, 50 + 50 * _boss_bars.size())
	add_child(b)
	_boss_bars.append(b)

## Combo counter (export.Batter): shown from 2 hits, fades out over 3.5 s after the last hit.
const COMBO_POS := Vector2(694.95, 234.95)
const COMBO_FADE := 3.5
const COMBO_DIGIT_END := 1.4 / 3.5
const COMBO_POP := 4.0 / 24.0
var _combo: Node2D
var _combo_tween: Tween

func show_combo(count: int) -> void:
	if count < 2:
		return
	if _combo == null:
		_combo = Node2D.new()
		_combo.position = COMBO_POS
		add_child(_combo)
	for c in _combo.get_children():
		c.queue_free()
	_combo.add_child(UiLayout.create("combo"))
	var digits := str(count)
	var x := 4.0 if count < 10 else (-44.6 if count < 100 else -95.6)
	for i in digits.length():
		var d := UiLayout.create("combo_num" + digits[i])
		d.position = Vector2(x + i * 50.0, 28.3)
		# num clip: pops from 3.5x to 1.4x over 4 frames (the extracted art is its first frame)
		d.scale = Vector2.ONE
		d.create_tween().tween_property(d, "scale", Vector2.ONE * COMBO_DIGIT_END, COMBO_POP)
		_combo.add_child(d)
	_combo.modulate.a = 1.0
	if _combo_tween:
		_combo_tween.kill()
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo, "modulate:a", 0.0, COMBO_FADE)

## "GO GO" arrow shown when a camera stop is cleared (StopPoint.destroy).
func play_gogo() -> void:
	var r := Rig.create("gogo")
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
	_ui.set_bar("hpline", float(h.hp) / h.max_hp)
	_ui.set_bar("mpline", float(h.mp) / h.max_mp)
	_ui.set_bar("expline", float(GameState.exp) / GameState.exp_to_next())
	_ui.set_bar("wsmc", float(h.rage) / h.data.rage_max)
	_ui.show_frame("shows", 1 if h.rage >= h.data.rage_max else 0)   # 无双 logo lights up when full
	_ui.set_text("txthp", "%d/%d" % [h.hp, h.max_hp])
	_ui.set_text("txtmp", "%d/%d" % [h.mp, h.max_mp])
	_ui.set_text("txtexp", "%d/%d" % [GameState.exp, GameState.exp_to_next()])
	_ui.set_text("txtlevel", str(GameState.level))
	# Wukong's learned skill i shows icon frame i + 1 (frame 0 = locked)
	var learned := [&"hit8", &"hit6", &"hit7", &"hit9", &"hit10"]
	for i in learned.size():
		_ui.show_frame("skill%d" % (i + 1), i + 1 if GameState.has_skill(learned[i]) else 0)
