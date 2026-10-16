@tool
class_name StatRow
extends Control
## One attribute row of the 背包 / 法宝 panels, as it lives in scenes/ui/<name>.tscn: a right-aligned `Caption` label on the
## left and a `Box` (a Panel whose StyleBoxFlat is saved in the scene) on the right, which holds the row's value Label.
## The three are ordinary nodes, so the user can move and resize a whole row, its box or its caption by hand in the editor;
## the value Label keeps its name and its `ui_piece` meta, wherever the row sits (UiLayout._wire_from_scene finds it).
## A Panel and Labels draw themselves in the editor, so the row has nothing to draw: the script is `@tool` only so the rows
## are instanced in the editor too.
##
## The rows come from a column layout in ui px: captions `caption_w` wide, a `GAP` between caption and box, every box
## `BOX_H` tall — the same numbers Backpack/SutraPanel's run-time builder used.

const BOX_H := 20.0
const GAP := 6.0
const CAPTION_SIZE := 14
const CAPTION_COLOR := Color("f3e3b0")
const BOX_BG := Color(0, 0, 0, 0)
const BOX_BORDER := Color("c9a45a")

## The box frame: black, 55% opaque, thin gold border, 3 px corners.
static func box_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BOX_BG
	sb.border_color = BOX_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	return sb

## One row: `Caption` (the caption text) + `Box` (the framed value) with `value` moved into the box. The row's rect is
## `caption_w` + GAP + `box_w` by BOX_H; place it in the panel yourself.
static func create_row(caption_text: String, caption_w: float, box_w: float, value: Label) -> StatRow:
	var row := StatRow.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size = Vector2(caption_w + GAP + box_w, BOX_H)
	var caption := Label.new()
	caption.name = "Caption"
	caption.text = caption_text
	caption.size = Vector2(caption_w, BOX_H)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", CAPTION_SIZE)
	caption.add_theme_color_override("font_color", CAPTION_COLOR)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 2)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(caption)
	var box := Panel.new()
	box.name = "Box"
	box.position = Vector2(caption_w + GAP, 0)
	box.size = Vector2(box_w, BOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", box_style())
	row.add_child(box)
	if value:
		value.owner = null   # it is handed to the box: the caller owns the row's subtree to the scene root
		value.get_parent().remove_child(value)
		box.add_child(value)   # keeps its name and its ui_piece meta: the layout reaches it wherever the row sits
		place_value_in_box(value)
	return row

## Puts a row's value Label in its box the way UiLayout.place_label_in_box() used to: left-aligned, 4 px in from the box's
## left edge, with the middle of its glyphs on the box's middle (the INK_MIDDLE rule: this font's glyphs ride INK_MIDDLE em
## below the top of their line). The label is anchored full-rect, so it is the box the user resizes.
static func place_value_in_box(value: Label) -> void:
	var font_size := float(value.get_theme_font_size("font_size"))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value.offset_left = 4.0
	value.offset_right = -4.0
	value.offset_top = value.get_parent().size.y / 2.0 - UiLayout.INK_MIDDLE * font_size
	value.offset_bottom = 0.0
