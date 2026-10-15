class_name BossBar
extends Node2D
## Boss HP gauge at the top of the screen (GameInfo.addBossBlood / BossBlood): the mask slides left as HP drops
## while the red fill stays put, so the red never leaves the gauge.
## The boss name was a per-boss bitmap (the `namemc` frames piece); it is now the display_name drawn in a marker font,
## centred on the (hidden) namemc area.

const EMPTY_SHIFT := -323.0   ## mask x offset at 0 HP relative to full (BossBlood frame 1 -> frame 100)

const NAME_FONT := preload("res://assets/fonts/GBai851Marker.ttf")
const NAME_AREA := Rect2(-69.9, -13.75, 101.3, 28.35)   ## union of the namemc frames' bounds, relative to the piece
const NAME_SIZE := 28   ## the original bitmap name ink is ~24 px tall; at this size the text ink is 23-26 px inside the 28.35 px area (a longer name is wider than the area, so it is centred as a whole)

var boss: Monster
var _ui: UiLayout
var _mask: Sprite2D
var _mask_x := 0.0
var _fill_x := {}   ## fill sprite -> its x (in the mask's space) at full HP

static func create(m: Monster) -> BossBar:
	var b := BossBar.new()
	b.boss = m
	return b

func _ready() -> void:
	_ui = UiLayout.create("boss_blood")
	add_child(_ui)
	_ui.set_visible_piece("namemc", false)   # the per-boss name bitmaps are replaced by text
	add_child(_name_label(boss.data.display_name))
	for sp: Sprite2D in _ui.find_children("*", "Sprite2D", true, false):
		if sp.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			_mask = sp
	if _mask:
		_mask_x = _mask.position.x
		for c: Node2D in _mask.get_children():
			_fill_x[c] = c.position.x

func _process(_dt: float) -> void:
	if not is_instance_valid(boss) or boss.state == Monster.State.DEAD:
		queue_free()
		return
	if _mask == null:
		return
	var shift := EMPTY_SHIFT * (1.0 - clampf(float(boss.hp) / boss.max_hp, 0.0, 1.0))
	_mask.position.x = _mask_x + shift
	for c: Node2D in _fill_x:
		c.position.x = _fill_x[c] - shift / _mask.scale.x   # the fill lives in the (scaled) mask's space

## The boss name as text, centred on the namemc piece's area (that piece is hidden).
func _name_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.position = _ui.piece_position("namemc") + NAME_AREA.position
	l.size = NAME_AREA.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", NAME_FONT)
	l.add_theme_font_size_override("font_size", NAME_SIZE)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	# the black glow of the original (GlowFilter blur 8, strength 5.4) as a shadow
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_outline_size", 8)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the area holds 2-4 glyphs; a longer name is wider than the area, so grow symmetrically around its centre
	var w := maxf(NAME_AREA.size.x, l.get_minimum_size().x)
	l.position.x -= (w - NAME_AREA.size.x) * 0.5
	l.size = Vector2(w, NAME_AREA.size.y)
	return l
