class_name StatRows
extends Control
## A grid of stat rows drawn by Godot: a caption (right-aligned label) on the left and a framed value box on the right.
## The original panels have their captions and value boxes baked into the art (and crooked); this replaces them with an
## aligned layout. The boxes are drawn by this Control, the values are the layout's own text labels moved into them
## (UiLayout.place_label_in_box), so the panel controls the text and this only the frame.

const BOX_H := 20.0
const GAP := 6.0
const CAPTION_SIZE := 14
const CAPTION_COLOR := Color("f3e3b0")
const BOX_BG := Color(0, 0, 0, 0.55)
const BOX_BORDER := Color("c9a45a")

var _boxes := {}   ## label name -> Rect2 of its box

## cols: one dictionary per column {x, y, row_h, caption_w, box_w, rows: [{caption, label, box_w?}]}. x is the left of the
## captions, y the top of the first row; row i sits at y + i * row_h (UI px).
static func create(cols: Array) -> StatRows:
	var r := StatRows.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var extent := Vector2.ZERO
	for col: Dictionary in cols:
		var x := float(col.x)
		var y := float(col.y)
		var row_h := float(col.row_h)
		var caption_w := float(col.caption_w)
		var rows: Array = col.rows
		for i in rows.size():
			var row: Dictionary = rows[i]
			var top := y + float(i) * row_h
			var caption := Label.new()
			caption.text = str(row.caption)
			caption.position = Vector2(x, top)
			caption.size = Vector2(caption_w, BOX_H)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			caption.add_theme_font_size_override("font_size", CAPTION_SIZE)
			caption.add_theme_color_override("font_color", CAPTION_COLOR)
			caption.add_theme_color_override("font_outline_color", Color.BLACK)
			caption.add_theme_constant_override("outline_size", 2)
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.add_child(caption)
			var box_w := float(row.get("box_w", col.box_w))
			var box := Rect2(x + caption_w + GAP, top, box_w, BOX_H)
			r._boxes[str(row.label)] = box
			extent = extent.max(box.end)
	r.size = extent
	return r

func box_rect(label_name: String) -> Rect2:
	return _boxes.get(label_name, Rect2())

func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BOX_BG
	sb.border_color = BOX_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	for label_name: String in _boxes:
		draw_style_box(sb, box_rect(label_name))
