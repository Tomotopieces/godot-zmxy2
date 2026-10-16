extends Node
## Second step of tools/render_item_art: turn, scale and place each raw art picture so it matches the item's original
## framed icon (assets/items/<id>.png), then write assets/items/fall_<id>.png.
##   godot --headless --path game res://tools/fit_item_art.tscn -- <raw dir>
## The icon's own drawing is found by comparing it with the empty frame every such icon shares
## (tools/item_art/frame_template.png); the art is tried at every angle (and mirrored) and kept where its outline
## overlaps the icon's drawing best. The result keeps the icon's inner window as its canvas (twice as large), so the
## picture sits in a cell where the icon's drawing sat.

const INNER := Rect2i(6, 7, 40, 41)   ## the icon's window inside the frame
const OUT_SCALE := 3                   ## the written picture is the window at this scale
const STEP_DEG := 3
const UPRIGHT_RANGE := 12              ## clothes, wings, treasures stand as in the game: only a slight turn is tried
## Weapons lie diagonally in their icons, on a dark backing the overlap search cannot tell from the blade: their turn
## is set by hand (degrees, mirrored), read off the original icon.
const WEAPON_TURN := {"nyd": [-45, false], "myz": [-40, true], "syc": [-40, true]}
const WEAPON_BOX := Rect2(1, 1, 38, 39)   ## a weapon fills the whole window diagonally, as in its icon

func _ready() -> void:
	get_tree().create_timer(600.0, true, false, true).timeout.connect(get_tree().quit.bind(2))
	var raw_dir := OS.get_cmdline_user_args()[0]
	var tmpl := Image.load_from_file(ProjectSettings.globalize_path("res://tools/item_art/frame_template.png"))
	tmpl.convert(Image.FORMAT_RGBA8)
	for f in DirAccess.get_files_at(raw_dir):
		if not f.ends_with(".png"):
			continue
		var id := f.get_basename()
		var raw := Image.load_from_file(raw_dir.path_join(f))
		raw.convert(Image.FORMAT_RGBA8)
		var icon := Image.load_from_file(ProjectSettings.globalize_path("res://assets/items/%s.png" % id))
		icon.convert(Image.FORMAT_RGBA8)
		var target := _icon_mask(icon, tmpl)
		var tb := _mask_bounds(target)
		if tb.size.x < 3:
			push_error("fit_item_art: %s: no drawing found in its icon" % id)
			continue
		var best := [-1.0, 0.0, false, 1.0, Vector2.ZERO]
		var degs: Array = range(-UPRIGHT_RANGE, UPRIGHT_RANGE + 1, STEP_DEG)
		var flips: Array = [false, true]
		if WEAPON_TURN.has(id):
			degs = [WEAPON_TURN[id][0]]
			flips = [WEAPON_TURN[id][1]]
		target = _dilate(target)   # a pixel of slack: thin things (blades, staffs) still overlap when nearly aligned
		for flip in flips:
			for deg in degs:
				var fit := _place(raw, deg, flip, WEAPON_BOX if WEAPON_TURN.has(id) else tb)
				var score := _iou(raw, deg, flip, fit[0], fit[1], target)
				if score > best[0]:
					best = [score, deg, flip, fit[0], fit[1]]
		var out := _render(raw, best[1], best[2], best[3], best[4])
		out.save_png(ProjectSettings.globalize_path("res://assets/items/fall_%s.png" % id))
		print("fitted %s angle=%d flip=%s overlap=%.2f" % [id, best[1], best[2], best[0]])
	get_tree().quit()

## 1 where the icon's window differs from the empty frame (its drawing).
func _icon_mask(icon: Image, tmpl: Image) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(INNER.size.x * INNER.size.y)
	for y in INNER.size.y:
		for x in INNER.size.x:
			var a := icon.get_pixel(INNER.position.x + x, INNER.position.y + y)
			var b := tmpl.get_pixel(INNER.position.x + x, INNER.position.y + y)
			var d := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			m[y * INNER.size.x + x] = 1.0 if d > 0.12 else 0.0
	return m

func _dilate(m: PackedFloat32Array) -> PackedFloat32Array:
	var o := m.duplicate()
	var w := INNER.size.x
	for y in INNER.size.y:
		for x in w:
			if m[y * w + x] > 0.5:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < INNER.size.y:
						o[q.y * w + q.x] = 1.0
	return o

func _mask_bounds(m: PackedFloat32Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for y in INNER.size.y:
		for x in INNER.size.x:
			if m[y * INNER.size.x + x] > 0.5:
				lo = lo.min(Vector2(x, y))
				hi = hi.max(Vector2(x + 1, y + 1))
	return Rect2(lo, hi - lo) if lo.x != INF else Rect2()

## Where a raw texel lands: turned `deg` (mirrored first), scaled `k`, its centre at `c` (window px).
func _xf(raw: Image, deg: int, flip: bool, k: float, c: Vector2) -> Transform2D:
	var half := Vector2(raw.get_size()) / 2.0
	var t := Transform2D.IDENTITY.translated(-half)
	if flip:
		t = Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO) * t
	t = Transform2D(deg_to_rad(deg), Vector2.ZERO) * t
	t = Transform2D.IDENTITY.scaled(Vector2(k, k)) * t
	return Transform2D.IDENTITY.translated(c) * t

## Scale and centre that put the turned art's outline on the icon drawing's box.
func _place(raw: Image, deg: int, flip: bool, tb: Rect2) -> Array:
	var x0 := _xf(raw, deg, flip, 1.0, Vector2.ZERO)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var n := raw.get_width()
	for y in range(0, raw.get_height(), 4):
		for x in range(0, n, 4):
			if raw.get_pixel(x, y).a > 0.3:
				var p := x0 * Vector2(x, y)
				lo = lo.min(p)
				hi = hi.max(p)
	var sz := hi - lo
	var k := minf(tb.size.x / maxf(sz.x, 1.0), tb.size.y / maxf(sz.y, 1.0))
	var c := tb.get_center() - (lo + hi) / 2.0 * k
	return [k, c]

func _iou(raw: Image, deg: int, flip: bool, k: float, c: Vector2, target: PackedFloat32Array) -> float:
	var inv := _xf(raw, deg, flip, k, c).affine_inverse()
	var inter := 0.0
	var uni := 0.0
	var size := raw.get_size()
	for y in INNER.size.y:
		for x in INNER.size.x:
			var p := inv * Vector2(x + 0.5, y + 0.5)
			var a := 0.0
			if p.x >= 0 and p.y >= 0 and p.x < size.x and p.y < size.y:
				a = 1.0 if raw.get_pixel(int(p.x), int(p.y)).a > 0.3 else 0.0
			var t := target[y * INNER.size.x + x]
			inter += minf(a, t)
			uni += maxf(a, t)
	return inter / maxf(uni, 1.0)

func _render(raw: Image, deg: int, flip: bool, k: float, c: Vector2) -> Image:
	var w := INNER.size.x * OUT_SCALE
	var h := INNER.size.y * OUT_SCALE
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var inv := _xf(raw, deg, flip, k, c).affine_inverse()
	var size := raw.get_size()
	for y in h:
		for x in w:
			var p := inv * (Vector2(x + 0.5, y + 0.5) / OUT_SCALE)
			if p.x >= 0 and p.y >= 0 and p.x < size.x - 1 and p.y < size.y - 1:
				out.set_pixel(x, y, _bilinear(raw, p))
	return out

func _bilinear(img: Image, p: Vector2) -> Color:
	var x := int(p.x)
	var y := int(p.y)
	var f := p - Vector2(x, y)
	var a := img.get_pixel(x, y).lerp(img.get_pixel(x + 1, y), f.x)
	var b := img.get_pixel(x, y + 1).lerp(img.get_pixel(x + 1, y + 1), f.x)
	return a.lerp(b, f.y)
