class_name ItemIcon
extends TextureRect
## An item in a cell (bag, worn slot, forge, shop): its ground picture (掉落物, no frame) fitted inside the cell with a
## margin, with a glow around its outline in the colour of its quality (优秀 green, 精良 blue, 史诗 purple, 传说 orange;
## 普通 none): the same halo as the hero's rage / anti-lock glow (SpriteFx), but still.

const MARGIN := 0.12        ## share of the cell left free on each side, so no picture reaches the frame
const GLOW_REACH := 6.0     ## px of the halo (the hero's breathes between 15 and 6)
const GLOW_STRENGTH := 1.5  ## as the hero's

static func create(item: Item, cell: float) -> ItemIcon:
	var d := GameState.item_data(item)
	var t := ItemIcon.new()
	t.size = Vector2(cell, cell)
	var m := cell * MARGIN
	t.texture = d.ground_icon if d.ground_icon != null else d.icon
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# the picture is drawn inside the margin: shrink the rect, then move it back to the cell's middle
	t.set_meta(&"cell", cell)
	t.custom_minimum_size = Vector2.ZERO
	t.size = Vector2(cell - 2.0 * m, cell - 2.0 * m)
	t.pivot_offset = t.size / 2.0
	t.set_meta(&"inset", m)
	if d.color.a > 0.0 and d.color != Color.WHITE:
		t.material = SpriteFx.glow_material(Color(d.color, 1.0), GLOW_REACH, GLOW_STRENGTH)
	return t

## Put the icon on the cell whose top left corner is `pos` (in the icon's parent).
func place(pos: Vector2) -> ItemIcon:
	position = pos + Vector2.ONE * float(get_meta(&"inset"))
	return self
