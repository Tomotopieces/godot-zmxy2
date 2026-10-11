extends Node
## Fits the text of the original interface layouts into the frames they are meant to sit in.
##
## The Flash layouts position a text field by hand over artwork that has the frame (a value box, a coloured band, a
## bar) baked in, with a different font and line height; the two never agree, and every screen came out a few pixels off
## in its own way. Nothing here guesses offsets: the layout is drawn without its text, and for every text field the
## frame around it is found in the picture itself (the nearest strong horizontal edges above and below the field), and
## written into the field's record as fit = [top, bottom] relative to the field. At run time the text is centred in that
## frame (src/ui/ui_layout.gd).
##
## Baked caption sheets (a picture holding every caption of a panel, laid out unevenly) are cut into one piece per caption
## and each piece is centred on the frame beside it.
##
##   godot --headless --path game res://tools/fit_ui.tscn            every layout
##   godot --headless --path game res://tools/fit_ui.tscn -- backpack hud
##
## Re-running is safe (fits are recomputed; a sheet already cut is left as it is).

const SHEETS := {"backpack": ["backpack_v5:16"]}   ## layout -> baked caption sheets to cut
const EDGE := 0.10                  ## row brightness change (0..1) that counts as the edge of a frame
const REACH := 2.2                  ## a frame must be within this many font sizes of the field's middle
const MIN_FRAME := 0.9              ## ... and at least this many font sizes high
const SKIP := ["save_slots"]         ## layouts whose fields share a plain slot (a title over a time): placed by their screen
const MIN_FRAME_OF := {"role_info": 0.5}   ## layouts whose frames are thin brush strokes (the HUD bars)

func _ready() -> void:
	var names: PackedStringArray = OS.get_cmdline_user_args()
	if names.is_empty():
		for d in DirAccess.get_directories_at("res://assets/ui"):
			if FileAccess.file_exists("res://assets/ui/%s/ui.json" % d):
				names.append(d)
	GameState.new_game("wukong")
	for n in names:
		await _fit(n)
	get_tree().quit()

func _strip(v) -> void:
	if v is Array:
		for x in v:
			_strip(x)
	elif v is Dictionary:
		v.erase("fit")
		for k in v:
			_strip(v[k])

## Draws the layout (its text hidden) on a black background. Returns {image, rects}: rects maps every text field's
## record to the field's rectangle in layout space.
func _render(ui: UiLayout) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(940, 590)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.size = Vector2(940, 590)
	vp.add_child(rect)
	vp.add_child(ui)
	add_child(vp)
	var rects := []
	for l: Label in ui.find_children("*", "Label", true, false):
		if l.has_meta(&"rec"):
			rects.append([l.get_meta(&"rec"), Rect2(l.global_position - ui.global_position, l.size)])
			l.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return {"image": img, "rects": rects}

## Mean brightness of row y over [x0, x1).
func _row(img: Image, y: int, x0: int, x1: int) -> float:
	var s := 0.0
	for x in range(x0, x1):
		var c := img.get_pixel(x, y)
		s += (c.r + c.g + c.b) / 3.0
	return s / float(maxi(x1 - x0, 1))

## Rows [first, last] of the picture standing just left of x (within 14 px) around row cy, [] when there is none or it is
## taller than a text line.
func _caption_rows(img: Image, x: int, cy: int, fs: float) -> Array:
	var x1 := clampi(x, 1, 939)
	var x0 := clampi(x - 14, 0, x1 - 1)
	var first := -1
	var last := -1
	var reach := int(fs * 1.6)
	for y in range(maxi(cy - reach, 0), mini(cy + reach, 589)):
		var lit := false
		for xx in range(x0, x1):
			var c := img.get_pixel(xx, y)
			if c.r + c.g + c.b > 0.35:
				lit = true
				break
		if lit:
			if first < 0:
				first = y
			last = y
	if first < 0 or float(last - first) > fs * 2.2 or float(last - first) < fs * 0.6:
		return []
	return [first, last]

## Finds the frame around every text field of layout `name` and stores it in the field's record.
func _fit(name: String) -> void:
	var path := "res://assets/ui/%s/ui.json" % name
	var passes := 2 if SHEETS.has(name) else 1
	if name in SKIP:
		passes = 1
	var report := ""
	for pass_i in passes:
		# fields are measured where the original put them: a fit from an earlier run must not move them first
		var clean = JSON.parse_string(FileAccess.get_file_as_string(path))
		_strip(clean)
		var ui := UiLayout.new()
		ui._d = clean
		ui.build_from_data()
		var d: Dictionary = ui._d
		var shot := await _render(ui)
		var img: Image = shot.image
		var fitted := 0
		for e in shot.rects:
			var rec: Dictionary = e[0]
			var r: Rect2 = e[1]
			rec.erase("fit")
			var lift := UiLayout.text_lift(float(rec.size))
			var fs := float(rec.size)
			if name in SKIP:
				continue
			var cy := int(r.get_center().y)
			var x0 := clampi(int(r.position.x + r.size.x * 0.2), 0, 939)
			var x1 := clampi(int(r.position.x + r.size.x * 0.8), x0 + 1, 940)
			if cy < 1 or cy > 588:
				continue
			var ref := _row(img, cy, x0, x1)
			var top := -1
			var bottom := -1
			for k in range(1, int(fs * REACH)):
				# the edge of a frame is a step between two rows (a gradient or a texture behind is not)
				if top < 0 and cy - k >= 0 and absf(_row(img, cy - k, x0, x1) - _row(img, cy - k + 1, x0, x1)) > EDGE:
					top = cy - k
				if bottom < 0 and cy + k < 590 and absf(_row(img, cy + k, x0, x1) - _row(img, cy + k - 1, x0, x1)) > EDGE:
					bottom = cy + k
			if top < 0 or bottom < 0 or float(bottom - top) < fs * float(MIN_FRAME_OF.get(name, MIN_FRAME)) or float(bottom - top) > fs * 2.4:
				# no frame: a caption right before the field (a picture of text) is what it belongs to - level with its middle
				var cap := _caption_rows(img, int(r.position.x), cy, fs)
				if cap.is_empty():
					continue
				top = cap[0]
				bottom = cap[1]
			rec["fit"] = [snappedf(float(top) + 0.5 - (r.position.y + lift), 0.5), snappedf(float(bottom) + 0.5 - (r.position.y + lift), 0.5)]
			fitted += 1
		report = "%s: %d of %d fields fitted" % [name, fitted, shot.rects.size()]
		if pass_i == 0 and SHEETS.has(name):
			var frames: Array[Rect2] = []
			for e in shot.rects:
				var rec: Dictionary = e[0]
				if rec.has("fit"):
					var r: Rect2 = e[1]
					frames.append(Rect2(r.position.x, r.position.y + UiLayout.text_lift(float(rec.size)) + float(rec.fit[0]), r.size.x, float(rec.fit[1]) - float(rec.fit[0])))
			var n_cut := _cut_sheets(name, d, frames)
			report += ", %d captions cut" % n_cut
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(d, " "))
		f.close()
		ui.free()
	print(report)

## Cuts the baked caption sheets of layout `name` into one leaf per caption, each centred on the frame beside it.
func _cut_sheets(name: String, d: Dictionary, frames: Array[Rect2]) -> int:
	var count := 0
	for n in d.nodes:
		if n.type != "art":
			continue
		var out := []
		for lf in n.leaves:
			if lf.size() > 3 or not SHEETS[name].has(lf[0]):
				out.append(lf)
				continue
			var info: Dictionary = d.textures[lf[0]]
			var tex: Image = load(info.res).get_image()
			var s := float(info.scale)
			for piece in _clusters(tex):
				var cy_ui: float = float(lf[1][5]) + float(info.oy) + (piece.position.y + piece.size.y / 2.0) / s
				var cx_ui: float = float(lf[1][4]) + float(info.ox) + (piece.position.x + piece.size.x / 2.0) / s
				var dy := 0.0
				var best := 24.0
				for fr in frames:
					# the frame in the same row, to the right of the caption
					if fr.position.x >= cx_ui - 4.0 and fr.position.x - cx_ui < 200.0 and absf(fr.get_center().y - cy_ui) < best:
						best = absf(fr.get_center().y - cy_ui)
						dy = fr.get_center().y - cy_ui
				var m: Array = lf[1].duplicate()
				m[5] = float(m[5]) + dy
				out.append([lf[0], m, lf[2], [piece.position.x, piece.position.y, piece.size.x, piece.size.y]])
				count += 1
		n.leaves = out
	return count

## Connected pieces of a picture's opaque pixels, merging pixels that are close (the letters of one caption).
func _clusters(img: Image) -> Array[Rect2]:
	var w := img.get_width()
	var h := img.get_height()
	var gx := 14
	var gy := 6
	var parent := {}
	var find := func(a: int) -> int:
		var r := a
		while parent.get(r, r) != r:
			r = parent[r]
		return r
	var boxes := {}
	var rows: Array = []
	# scan runs per row, then merge runs of nearby rows
	var runs_prev: Array = []
	var next_id := 0
	var all: Array = []   ## [x0, x1, y, id]
	for y in range(h):
		var x := 0
		var runs: Array = []
		while x < w:
			if img.get_pixel(x, y).a > 0.15:
				var x0 := x
				while x < w and img.get_pixel(x, y).a > 0.15:
					x += 1
				runs.append([x0, x - 1, y, next_id])
				parent[next_id] = next_id
				next_id += 1
			else:
				x += 1
		rows.append(runs)
	for y in range(h):
		for run in rows[y]:
			for dy in range(0, gy + 1):
				if y - dy < 0:
					break
				for other in rows[y - dy]:
					if other[3] == run[3]:
						continue
					if run[0] - gx <= other[1] and other[0] - gx <= run[1]:
						var a: int = find.call(run[3])
						var b: int = find.call(other[3])
						if a != b:
							parent[a] = b
	for y in range(h):
		for run in rows[y]:
			var root: int = find.call(run[3])
			var r := Rect2(run[0], run[2], run[1] - run[0] + 1, 1)
			boxes[root] = r if not boxes.has(root) else (boxes[root] as Rect2).merge(r)
	var out: Array[Rect2] = []
	for k in boxes:
		out.append((boxes[k] as Rect2).grow(1.0).intersection(Rect2(0, 0, w, h)))
	return out
