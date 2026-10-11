extends Node
## Finds spots where a stage's art leaves thin gaps (seams between pieces, slivers at the screen edges): the
## far layer is hidden and the screen cleared to magenta, every stage is rendered at camera steps, and runs of
## at most MAX_GAP magenta pixels between art (or against the screen edge) are reported. Open sky is ignored.
##   godot --path game --position 6000,6000 res://tools/seam_check.tscn -- [--scale=1.58] [--out=<dir>]

const KEY := Color(1, 0, 1)
const STEP := 235.37   ## not a whole number: the camera also sits between pixels while scrolling
const MAX_GAP := 4
const KEY2 := Color(0, 1, 0)

## Partly see-through pixels (the clear colour changes them) on a 1-2 px line between opaque art: seams where
## two anti-aliased texture edges meet.
func _see_through(a: Image, b: Image) -> Array:
	var out := []
	var w := a.get_width()
	var h := a.get_height()
	var thru := func(x: int, y: int) -> bool:
		var ca := a.get_pixel(x, y)
		var cb := b.get_pixel(x, y)
		return absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.08
	var opaque := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= w or y >= h:
			return false
		return not thru.call(x, y)
	for y in range(1, h - 2):
		for x in range(0, w, 3):
			if thru.call(x, y) and opaque.call(x, y - 1) and (opaque.call(x, y + 1) or (thru.call(x, y + 1) and opaque.call(x, y + 2))):
				out.append(Vector2i(x, y))
	for x in range(1, w - 2):
		for y in range(0, h, 3):
			if thru.call(x, y) and opaque.call(x - 1, y) and (opaque.call(x + 1, y) or (thru.call(x + 1, y) and opaque.call(x + 2, y))):
				out.append(Vector2i(x, y))
	return out

var _out := ""
var _only: PackedStringArray = []   ## --only=sl21,sl31: just these stages

func _ready() -> void:
	var scale := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scale="):
			scale = a.substr(8).to_float()
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",")
		elif a.begins_with("--out="):
			_out = a.substr(6)
	get_window().size = Vector2i(Layers.VIEW * scale)
	await get_tree().process_frame
	RenderingServer.set_default_clear_color(KEY)
	var bad := 0
	for x in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]:
		for y in ([1, 2, 3] if x <= 3 else ([1, 2, 3, 4, 5, 6] if x == 10 else [1])):
			var s := Vector2i(x, y)
			if not ResourceLoader.exists("res://assets/levels/%s/level.json" % Level.scene_name(s)):
				continue
			if not _only.is_empty() and not Level.scene_name(s) in _only:
				continue
			bad += await _check(s)
	print("SEAM CHECK %s" % ("OK" if bad == 0 else "FOUND %d" % bad))
	get_tree().quit()

static func _key(img: Image, x: int, y: int) -> bool:
	var c := img.get_pixel(x, y)
	return c.r > 0.9 and c.g < 0.1 and c.b > 0.9

## Clearly art (not sky blending into the key colour): a gap between two such pixels is a seam.
static func _solid(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return true   # the screen edge closes a sliver
	var c := img.get_pixel(x, y)
	return Vector3(c.r - KEY.r, c.g - KEY.g, c.b - KEY.b).length() > 0.8

## Pixels of magenta runs no longer than MAX_GAP, closed by art on both sides or by art and the screen edge.
func _thin_gaps(img: Image) -> Array:
	var out := []
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h, 3):
		var x := 0
		while x < w:
			if not _key(img, x, y):
				x += 1
				continue
			var x0 := x
			while x < w and _key(img, x, y):
				x += 1
			if x - x0 <= MAX_GAP and (x0 > 0 or x < w) and _solid(img, x0 - 2, y) and _solid(img, x + 1, y):
				out.append(Vector2i(x0, y))
	for x in range(0, w, 3):
		var y := 0
		while y < h:
			if not _key(img, x, y):
				y += 1
				continue
			var y0 := y
			while y < h and _key(img, x, y):
				y += 1
			if y - y0 <= MAX_GAP and (y0 > 0 or y < h) and _solid(img, x, y0 - 2) and _solid(img, x, y + 1):
				out.append(Vector2i(x, y0))
	return out

## Seams are straight: many gap pixels on one screen column (vertical) or row (horizontal). Holes in the art
## (sky between leaves) are scattered and ignored.
const MIN_LINE := 12

var _spots: Array = []   ## screen point on each reported line (for the crops)

func _straight(hits: Array) -> Array:
	var cols := {}
	var rows := {}
	for h: Vector2i in hits:
		cols[h.x] = cols.get(h.x, 0) + 1
		rows[h.y] = rows.get(h.y, 0) + 1
	var out := []
	_spots.clear()
	for x in cols:
		if cols[x] >= MIN_LINE:
			out.append("x=%d (%d)" % [x, cols[x]])
			_spots.append(hits[hits.find_custom(func(h): return h.x == x)])
	for y in rows:
		if rows[y] >= MIN_LINE:
			out.append("y=%d (%d)" % [y, rows[y]])
			_spots.append(hits[hits.find_custom(func(h): return h.y == y)])
	return out

func _check(s: Vector2i) -> int:
	GameState.new_game()
	var lv := Level.new()
	lv.stage = s
	add_child(lv)
	await get_tree().process_frame
	(lv.get_child(0) as CanvasLayer).visible = false   # the far background
	lv.hero.visible = false
	lv.hero.process_mode = Node.PROCESS_MODE_DISABLED
	lv.set_physics_process(false)   # the camera is driven by the check
	var found := 0
	var vx := 0.0
	var last := maxf(lv._end_x - Layers.VIEW.x, 0.0)
	while true:
		lv.camera.position = Vector2(vx, 0)
		lv.camera.force_update_scroll()
		lv.view_x = vx
		RenderingServer.set_default_clear_color(KEY)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		RenderingServer.set_default_clear_color(KEY2)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img2 := get_viewport().get_texture().get_image()
		var hits := _thin_gaps(img) + _see_through(img, img2)
		var lines := _straight(hits)
		if not lines.is_empty():
			found += 1
			print("%s view_x %d: %s" % [Level.scene_name(s), vx, lines])
			if _out != "":
				# a 5x crop of the stage art (no key colour change) around each line
				for i in _spots.size():
					var p: Vector2i = _spots[i]
					var r := Rect2i(p.x - 40, p.y - 12, 80, 24).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
					var c := img.get_region(r)
					c.resize(c.get_width() * 5, c.get_height() * 5, Image.INTERPOLATE_NEAREST)
					c.save_png("%s/seam_%s_%d_%d.png" % [_out, Level.scene_name(s), vx, i])
		if vx >= last:
			break
		vx = minf(vx + STEP, last)
	lv.queue_free()
	await get_tree().process_frame
	return found
