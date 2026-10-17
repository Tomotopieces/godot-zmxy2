class_name ItemTip
extends Control
## Hover panel describing an item, laid out like the original (export.pack.AttributeCon): 25 px rows from
## (20, 10) inside a black 70 % box with a thin white rounded border. Name in the quality colour; 品质 / 类型 /
## 等级 / 成长率 / 五行 rows (black label with a white glow, fading white underline, value after it);
## stats in orange ("攻击： 130(+12)"); white description wrapped at 135 px; "价值 : N 灵魂".
## Shared by the bag, forge and shop screens. Placed at the hovered icon + (25, 30) as in ShowObj.

const ROW := 25.0
const PAD := Vector2(20, 10)
const OFFSET := Vector2(25, 30)
const DESC_WIDTH := 135.0
const UNDERLINE := 80.0
const STAT_COLOR := Color("#ff9933")
const VALUE_COLOR := Color("#ff9933")
const TYPE_NAMES := {&"weapon": "武器", &"cloth": "防具", &"accessory": "饰 品", &"treasure": "法 宝",
	&"fashion": "时装", &"wing": "翅 膀", &"item": "道具"}
## stat -> [label, percent]
const STATS := [["hp", "生命", false], ["mp", "魔法", false], ["atk", "攻击", false], ["def", "防御", false],
	["crit", "暴击", true], ["miss", "闪避", true], ["hp_regen", "回血", false], ["mp_regen", "回魔", false],
	["lifesteal", "吸血", true], ["mdef", "魔抗", true], ["deephit", "重击", true]]
## materials whose stats only matter for fusion (贪 / 嗔 / 痴) show none, as in the original
const NO_STATS := ["t", "c", "ch"]

var _box: Panel
var _rows: Control
var _y := 0.0
var _w := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = Layers.Z_TIP
	_box = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.7)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	_box.add_theme_stylebox_override("panel", sb)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_rows = Control.new()
	_rows.position = PAD
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)
	visible = false

## Show for the icon `at`, kept on screen.
func show_for(item: Item, at: Control, _cell_w := 50.0) -> void:
	_build(item)
	visible = true
	var p := at.global_position + OFFSET
	position = p.clamp(Vector2.ZERO, Layers.VIEW - _box.size)

func _build(item: Item) -> void:
	for c in _rows.get_children():
		c.queue_free()
	_y = 0.0
	_w = 0.0
	var d := GameState.item_data(item)
	var plus := item.plus
	_label(d.display_name + ("(+%d)" % plus if plus > 0 else ""), Vector2(0, _y), d.color, 16)
	_y += ROW
	if d.quality != "":
		_pair("品质", _spaced(d.quality), d.color)
	var type_name: String = TYPE_NAMES.get(d.type, String(d.type))
	if d.stone > 0:
		type_name = "强化石"
	elif d.charm == &"luck":
		type_name = "幸运符"
	elif d.charm == &"keep":
		type_name = "神恩符"
	_pair("类型", type_name + ("·" + d.user if d.user != "" else ""), Color.WHITE)
	if Forge.is_treasure(item):
		_pair("等级", "Lv.%d" % item.lv, Color.WHITE)
		_pair("成长率", "%.1f" % item.growth, Color.WHITE)
		_pair("五行", Forge.element_text(item), Color.WHITE)
	if not item.id in NO_STATS:
		var stats := item.stats
		for s in STATS:
			var v := float(stats.get(s[0], 0.0))
			var extra := plus * float(d.strengthen.get(s[0], 0.0))
			if is_zero_approx(v) and is_zero_approx(extra):
				continue
			var txt: String = s[1] + "： " + _num(v, s[2])
			if not is_zero_approx(extra):
				txt += "(%s%s)" % ["+" if extra > 0 else "", _num(extra, s[2], false)]
			_label(txt, Vector2(0, _y), STAT_COLOR, 16, true)
			_y += ROW
	if d.desc != "":
		var l := _label(d.desc, Vector2(0, _y), Color.WHITE, 14, false, DESC_WIDTH)
		_y += maxf(ROW, roundf((l.get_minimum_size().y + 10.0) / ROW) * ROW)
	_label("价值 : %d 灵魂" % d.value, Vector2(0, _y), VALUE_COLOR, 14)
	_y += ROW
	_box.size = Vector2(_w + 35, _y + PAD.y + 10)

## Label row: glowing black label, white underline fading out, value in `color`.
func _pair(label: String, value: String, color: Color) -> void:
	var l := _label(label, Vector2(0, _y), Color.BLACK, 16, true)
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 4)
	var lw := l.get_minimum_size().x + 6
	var line := Line2D.new()
	line.width = 2
	line.points = PackedVector2Array([Vector2(lw - 4, _y + ROW - 6), Vector2(lw - 4 + UNDERLINE, _y + ROW - 6)])
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(120.0 / 255.0, Color.WHITE)
	line.gradient = g
	_rows.add_child(line)
	var v := _label("  " + value, Vector2(lw, _y - 1), color, 16)
	_w = maxf(_w, lw + maxf(v.get_minimum_size().x, UNDERLINE))
	_y += ROW

## wrap > 0: wrapped at that width (the description).
func _label(text: String, pos: Vector2, color: Color, size: int, bold := false, wrap := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	if wrap > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size.x = wrap
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", _bold_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(l)
	_w = maxf(_w, pos.x + l.get_minimum_size().x)
	return l

const BOLD_FONT := preload("res://assets/fonts/LXGW975HeiSC-400W.ttf")

static func _bold_font() -> Font:
	return BOLD_FONT

## "传说" -> "传 说" (the original quality strings are spaced).
static func _spaced(q: String) -> String:
	return " ".join(q.split("")) if q.length() == 2 else q

## Integers as is; percentages with up to two decimals (AUtils.changeNumber).
static func _num(v: float, percent: bool, with_sign_unit := true) -> String:
	if not percent:
		return str(int(v))
	var s := str(snappedf(v * 100.0, 0.01))
	if s.ends_with(".0"):
		s = s.trim_suffix(".0")
	return s + ("%" if with_sign_unit else "")
