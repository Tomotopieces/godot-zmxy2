extends Node
## UI prototype with the ink-brush kit (tools/ui_ink/build.js -> assets/ui_ink): HUD plate and bars, an item tooltip and
## the use menu, put together the way the game would (9-slice panels, progress bars, labels).
##   godot --path game --position 6000,6000 res://tools/ui_ink_proto.tscn -- <out.png> [stage]

const DIR := "res://assets/ui_ink/"
var _manifest: Dictionary

func _ready() -> void:
	_manifest = JSON.parse_string(FileAccess.get_file_as_string(DIR + "ink.json"))
	var args := OS.get_cmdline_user_args()
	var bg := TextureRect.new()
	bg.texture = load("res://assets/shared/06b9a7640ad6a413c05a32e9ed588287.png")
	bg.size = Layers.VIEW
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)
	_hud(Vector2(6, 2))
	_tooltip(Vector2(560, 50), Vector2(250, 190))
	_menu(Vector2(60, 230))
	_panel(Vector2(330, 300), Vector2(260, 150))
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0])
	get_tree().quit()

## A 9-slice picture drawn at `size` game px (the pictures are made at 2x, so it is a half-scale NinePatchRect).
func _nine(name: String, pos: Vector2, size: Vector2) -> NinePatchRect:
	var m: Dictionary = _manifest[name]
	var n := NinePatchRect.new()
	n.texture = load(DIR + name + ".png")
	var k := int(m.margin)
	n.patch_margin_left = k
	n.patch_margin_right = k
	n.patch_margin_top = k
	n.patch_margin_bottom = k
	n.position = pos
	n.size = size * 2.0
	n.scale = Vector2(0.5, 0.5)
	add_child(n)
	return n

func _pic(name: String, pos: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(DIR + name + ".png")
	t.position = pos
	t.scale = Vector2(0.5, 0.5)
	add_child(t)
	return t

func _bar(pos: Vector2, fill: String, value: float) -> void:
	_pic("bar_frame", pos)
	var p := TextureProgressBar.new()
	p.texture_progress = load(DIR + fill + ".png")
	p.min_value = 0.0
	p.max_value = 1.0
	p.step = 0.001
	p.value = value
	p.position = pos + Vector2(6, 6)
	p.scale = Vector2(0.5, 0.5)
	add_child(p)

func _label(t: String, pos: Vector2, size: int, color := Color.WHITE, outline := 4) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", outline)
	add_child(l)
	return l

func _hud(at: Vector2) -> void:
	_pic("hud_plate", at)
	var face := TextureRect.new()
	face.texture = load("res://icon.png")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.position = at + Vector2(14, 14)
	face.size = Vector2(50, 50)
	add_child(face)
	_bar(at + Vector2(66, 14), "bar_hp", 0.82)
	_bar(at + Vector2(66, 32), "bar_mp", 0.55)
	_bar(at + Vector2(66, 48), "bar_exp", 0.3)
	_label("820 / 1000", at + Vector2(78, 13), 11, Color.WHITE, 3)
	_label("110 / 200", at + Vector2(78, 31), 10, Color.WHITE, 3)
	_label("24", at + Vector2(20, 44), 15, Color("e8b84a"), 4)

func _tooltip(at: Vector2, size: Vector2) -> void:
	_nine("tooltip", at, size)
	_label("凝月刀", at + Vector2(24, 20), 20, Color("ff8a2a"))
	var rule := ColorRect.new()
	rule.position = at + Vector2(22, 50)
	rule.size = Vector2(size.x - 44, 1)
	rule.color = Color(Color("e8b84a"), 0.5)
	add_child(rule)
	var lines := ["品质  传说", "类型  武器 · 悟空", "攻击  124   暴击  20%", "强化  +3", "价值  320 灵魂"]
	for i in lines.size():
		_label(lines[i], at + Vector2(24, 58 + 22 * i), 14, Color.WHITE, 3)

func _menu(at: Vector2) -> void:
	_nine("panel", at, Vector2(230, 250))
	var names := ["使用", "兑换大月饼", "兑换武器", "丢掉"]
	for i in names.size():
		var kind := "btn_off" if i == 0 else ("btn_hover" if i == 2 else "btn")
		var p := at + Vector2(31, 30 + 48 * i)
		_pic(kind, p)
		var l := _label(names[i], p, 16, Color("2a1800") if i != 0 else Color("a8a4b0"), 0)
		l.size = Vector2(168, 52)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _panel(at: Vector2, size: Vector2) -> void:
	_nine("panel", at, size)
	var t := _pic("title_stroke", at + Vector2(size.x / 2.0 - 75.0, -14))
	t.modulate = Color.WHITE
	var l := _label("活动", at + Vector2(size.x / 2.0 - 20.0, -10), 20, Color("f4ecd8"), 0)
	l.size = Vector2(40, 28)
	_label("每天只能进入一次副本。", at + Vector2(30, 40), 15, Color("f4ecd8"), 0)
	_label("击败风神盾，防御 +50。", at + Vector2(30, 66), 15, Color("e8b84a"), 0)
