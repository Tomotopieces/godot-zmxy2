class_name ItemIcon
extends TextureRect
## An item in a cell (bag, worn slot, forge, shop): its ground picture (掉落物, no frame) fitted inside the cell with a
## margin; an item with no ground picture of its own shows the original framed icon instead, its frame stretched onto
## the cell's; equipment with a glow around its outline in the colour of its quality (普通 white, 优秀 green, 精良 blue, 史诗 purple,
## 传说 orange): the same halo as the hero's rage / anti-lock glow (SpriteFx), but still.

const MARGIN := 0.12        ## share of the cell left free on each side, so no picture reaches the frame
## Only equipment shows its quality as a glow (道具 and 时装 do not).
const GLOW_TYPES := [&"weapon", &"cloth", &"accessory", &"treasure", &"wing"]
const ICON_FRAME := Rect2(2, 3, 48, 48)   ## the frame inside an original framed icon (52 x 55 px)
const GLOW_REACH := 6.0     ## px of the halo (the hero's breathes between 15 and 6)
const GLOW_STRENGTH := 1.5  ## as the hero's

static func create(item: Item, cell: float) -> ItemIcon:
	var d := GameState.item_data(item)
	var t := ItemIcon.new()
	t.size = Vector2(cell, cell)
	var framed := d.ground_icon == null or d.ground_icon == d.icon
	var m := 0.0 if framed else cell * MARGIN
	if framed:
		var at := AtlasTexture.new()   # just the frame, so it lies exactly on the cell
		at.atlas = d.icon
		at.region = ICON_FRAME
		t.texture = at
	else:
		t.texture = d.ground_icon
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE if framed else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# the picture is drawn inside the margin: shrink the rect, then move it back to the cell's middle
	t.set_meta(&"cell", cell)
	t.set_meta(&"item", item)   # (AgentBridge names the icon after it)
	t.custom_minimum_size = Vector2.ZERO
	t.size = Vector2(cell - 2.0 * m, cell - 2.0 * m)
	t.pivot_offset = t.size / 2.0
	t.set_meta(&"inset", m)
	if not framed and d.color.a > 0.0 and d.type in GLOW_TYPES:   # a framed icon shows its quality as it always did
		t.material = SpriteFx.glow_material(Color(d.color, 1.0), GLOW_REACH, GLOW_STRENGTH)
	return t

## Put the icon on the cell whose top left corner is `pos` (in the icon's parent).
func place(pos: Vector2) -> ItemIcon:
	position = pos + Vector2.ONE * float(get_meta(&"inset"))
	return self
