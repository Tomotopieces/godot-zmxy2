extends Node
## UI prototype: the HUD frame, an item tooltip and a menu rebuilt with Godot's own controls (StyleBoxFlat, theme
## overrides, a little shader) instead of the original's baked pictures - to judge how far a native redo gets.
##   godot --path game --position 6000,6000 res://tools/ui_proto.tscn -- <out.png>

const INK := Color("0d0b12")
const GOLD := Color("e8b84a")
const GOLD_DARK := Color("8a5d1c")
const PARCHMENT := Color("2a2430")

func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://assets/shared/levels/1_v6_1.png")
	bg.size = Layers.VIEW
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)
	_hud(Vector2(14, 12))
	_tooltip(Vector2(560, 60))
	_menu(Vector2(120, 250))
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()

func _box(fill: Color, border: Color, radius := 10, width := 2, shadow := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb

func _bar(pos: Vector2, size: Vector2, value: float, top: Color, bottom: Color) -> Control:
	var back := Panel.new()
	back.position = pos
	back.size = size
	back.add_theme_stylebox_override("panel", _box(Color(0.05, 0.04, 0.07, 0.9), Color(0, 0, 0, 0.9), int(size.y / 2), 2, 0))
	var fill := Panel.new()
	fill.position = Vector2(2, 2)
	fill.size = Vector2((size.x - 4) * value, size.y - 4)
	var sb := _box(bottom, Color(0, 0, 0, 0), int(size.y / 2) - 2, 0, 0)
	sb.bg_color = top
	sb.border_blend = true
	fill.add_theme_stylebox_override("panel", sb)
	back.add_child(fill)
	var shine := ColorRect.new()   # the glossy upper half
	shine.position = Vector2(4, 3)
	shine.size = Vector2(maxf((size.x - 8) * value, 0.0), (size.y - 6) / 2.0)
	shine.color = Color(1, 1, 1, 0.22)
	back.add_child(shine)
	return back

func _hud(at: Vector2) -> void:
	var frame := Panel.new()
	frame.position = at
	frame.size = Vector2(250, 74)
	frame.add_theme_stylebox_override("panel", _box(Color(INK, 0.82), GOLD_DARK, 14, 2))
	add_child(frame)
	var portrait := Panel.new()
	portrait.position = at + Vector2(8, 8)
	portrait.size = Vector2(58, 58)
	portrait.add_theme_stylebox_override("panel", _box(PARCHMENT, GOLD, 29, 3, 0))
	add_child(portrait)
	var face := TextureRect.new()
	face.texture = load("res://icon.png")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.position = at + Vector2(11, 11)
	face.size = Vector2(52, 52)
	add_child(face)
	add_child(_bar(at + Vector2(76, 12), Vector2(160, 16), 0.82, Color("ff5a4a"), Color("a01818")))
	add_child(_bar(at + Vector2(76, 32), Vector2(160, 14), 0.55, Color("5aa8ff"), Color("1850a8")))
	add_child(_bar(at + Vector2(76, 51), Vector2(160, 8), 0.3, Color("d8d8f0"), Color("8888a8")))
	_label("820 / 1000", at + Vector2(80, 11), 12)
	_label("110 / 200", at + Vector2(80, 31), 11)
	_label("24", at + Vector2(10, 46), 16, GOLD)

func _label(t: String, pos: Vector2, size: int, color := Color.WHITE) -> void:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)

func _tooltip(at: Vector2) -> void:
	var p := Panel.new()
	p.position = at
	p.size = Vector2(250, 170)
	p.add_theme_stylebox_override("panel", _box(Color(INK, 0.92), GOLD, 8, 2, 14))
	add_child(p)
	var title := Label.new()
	title.text = "凝月刀"
	title.position = at + Vector2(14, 10)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("ff8a2a"))
	add_child(title)
	var lines := ["品质  传说", "类型  武器 · 悟空", "攻击  124   暴击  20%", "强化  +3", "价值  320 灵魂"]
	for i in lines.size():
		_label(lines[i], at + Vector2(14, 44 + 24 * i), 14)
	var rule := ColorRect.new()
	rule.position = at + Vector2(12, 38)
	rule.size = Vector2(226, 1)
	rule.color = Color(GOLD, 0.5)
	add_child(rule)

func _menu(at: Vector2) -> void:
	var p := Panel.new()
	p.position = at
	p.size = Vector2(170, 150)
	p.add_theme_stylebox_override("panel", _box(Color(INK, 0.9), GOLD_DARK, 12, 2, 12))
	add_child(p)
	var names := ["使用", "兑换大月饼", "兑换武器", "丢掉"]
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.position = at + Vector2(12, 12 + 33 * i)
		b.size = Vector2(146, 28)
		b.focus_mode = Control.FOCUS_NONE
		var normal := _box(Color("c88a1c") if i != 0 else Color("4a4650"), Color("ffd870") if i != 0 else Color("6a6670"), 6, 1, 0)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", _box(Color("e8a82c"), Color.WHITE, 6, 1, 0))
		b.add_theme_color_override("font_color", Color("2a1800") if i != 0 else Color("9a96a0"))
		b.add_theme_font_size_override("font_size", 15)
		add_child(b)
