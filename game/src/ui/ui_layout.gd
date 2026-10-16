class_name UiLayout
extends Control
## Screen built from an original interface layout (assets/ui/<name>/ui.json, written by tools/rig/extract_ui.js).
## Node kinds: art (static sprites), frames (one visible frame), bar (clipped fill), text (Label), button.
## Named pieces are reachable with art(), frames(), text(), set_bar(); buttons emit `button_pressed`.
##
## create() prefers the editor scene scenes/ui/<name>.tscn (written once by tools/ui_to_scene.gd from the same json, then
## arranged by hand); without it the layout is built from the json. Both origins wire the same way: every node carries the
## pieces the code reaches it by in `ui_piece`, a button its name in `ui_button`, a bar holder its travel in `ui_bar`, and
## _wire_from_scene() walks the tree and rebuilds _named / the buttons / the bars from those metas. A node may therefore be
## moved anywhere by hand, but must keep its name and its metas (a button's Up / Over / Down children and a bar's Clip /
## Content are looked up by name).

signal button_pressed(button_name: String)

const INK_MIDDLE := 0.55   ## where the middle of this font's glyphs lies below the top of the line, in em
const SCENE_PATH := "res://scenes/ui/%s.tscn"

var _d: Dictionary
var _named := {}     ## name -> Node (art / frames holder / Label / button Control)
var _bars := {}      ## path -> {clip, content, full: Vector2, empty: Vector2}
var _from_scene := false   ## the tree was instantiated from scenes/ui/: wired in _ready()

static func create(ui_name: String) -> UiLayout:
	var scene_path := SCENE_PATH % ui_name
	if ResourceLoader.exists(scene_path):
		var scene_ui := (load(scene_path) as PackedScene).instantiate() as UiLayout
		scene_ui._from_scene = true
		return scene_ui
	var u := UiLayout.new()
	u.build("res://assets/ui/%s/ui.json" % ui_name)
	return u

func _ready() -> void:
	# also wired when placed by hand in another scene: such an instance was not made by create() and has no _d
	if _from_scene or _d.is_empty():
		_wire_from_scene()

func build(path: String) -> void:
	_d = JSON.parse_string(FileAccess.get_file_as_string(path))
	build_from_data()

## Builds the nodes from the layout data in `_d` (tools/fit_ui.gd hands in data of its own) and wires them.
func build_from_data() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in _d.nodes:
		var node: Node
		match n.type:
			"art":
				node = _leaves(n.leaves, _m(n.m))
				node.name = "Art"
			"frames":
				node = _frames_node(n.frames, n.get("labels", {}), _m(n.m))
				# clips nested in one of the frames, driven separately ("parent/child")
				for q in n.get("nested", []):
					var sub := _frames_node(q.frames, q.get("labels", {}), _m(q.m))
					node.get_child(int(q.frame)).add_child(sub, true)
					var key: String = "%s/%s" % [n.name, q.name]
					# the same clip name differs per frame (a page per hero)
					_piece_keys(sub, [key, "%s@%d" % [key, int(q.frame)]])
			"bar":
				node = _bar(n)
			"text":
				node = _text(n)
				node.set_meta(&"rec", n)   # (tools/fit_ui.gd writes the frame a field sits in back into its record)
			"button":
				node = _button(n)
		if node == null:
			continue
		if n.name != null:
			node.name = String(n.name)
			_piece_keys(node, [n.name])
			if n.type == "button":
				node.set_meta(&"ui_button", String(n.name))   # a button emits the layout's name of it, not the node's
		add_child(node, true)
	_wire_from_scene()

func get_piece(piece: String) -> Node:
	return _named.get(piece)

func set_text(piece: String, t: String) -> void:
	var l: Label = _named.get(piece)
	if l:
		l.text = t

## Text fields nested inside a piece (e.g. a slot's txt_name), on every frame of it.
func set_inner_text(piece: String, field: String, t: String) -> void:
	var p: Node = _named.get(piece)
	if p:
		for l in p.find_children(field, "Label", true, false):
			l.text = t

## Make a frames piece clickable: hit area = bounds of all its frames; optional hover frame.
## Emits button_pressed(piece). Returns the hit Control.
func make_clickable(piece: String, hover_frame := -1, rest_frame := 0) -> Control:
	var p: Node2D = _named.get(piece)
	if p == null:
		return null
	var r := Rect2()
	for sp: Sprite2D in p.find_children("*", "Sprite2D", true, false):
		var sr := _local_rect(self, sp)
		r = sr if r.size == Vector2.ZERO else r.merge(sr)
	var b := Control.new()
	b.position = r.position
	b.size = r.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	PadNav.mark(b)
	add_child(b)
	if hover_frame >= 0:
		b.mouse_entered.connect(func(): show_frame(piece, hover_frame))
		b.mouse_exited.connect(func(): show_frame(piece, b.get_meta(&"rest", rest_frame)))
	b.set_meta(&"rest", rest_frame)
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			button_pressed.emit(piece))
	return b

## Sprite rect in the space of ancestor `p`.
func _local_rect(p: Node, sp: Sprite2D) -> Rect2:
	var xf := sp.transform
	var n := sp.get_parent()
	while n != p and n != null:
		if n is Node2D:
			xf = (n as Node2D).transform * xf
		n = n.get_parent()
	return xf * Rect2(Vector2.ZERO, sp.texture.get_size())

## Position of a named piece in layout space.
func piece_position(piece: String) -> Vector2:
	var p: Node2D = _named.get(piece)
	var xf := Transform2D.IDENTITY
	var n: Node = p
	while n != self and n != null:
		if n is Node2D:
			xf = (n as Node2D).transform * xf
		n = n.get_parent()
	return xf.origin

## Hide all unnamed artwork (keep buttons, texts and named pieces), for overlaying on another copy of the art.
func hide_unnamed() -> void:
	var keep := _named.values()
	for c in get_children():
		if c is Node2D and not c in keep:
			c.visible = false

## Hide / show any named piece.
func set_visible_piece(piece: String, v: bool) -> void:
	var p = _named.get(piece)
	if p:
		p.visible = v

## Pulsing outer glow on a piece (or one frame of it): the original animates a GlowFilter's blur and strength
## up and back down (lit 无双 logo, the next stage on the map). Rebuilt as a halo material of the sprites, pulsed by a tween.
func glow_pulse(target: Node2D, color: Color, blur: Vector2, strength: Vector2, half: float) -> void:
	var mat := SpriteFx.glow_material(color, blur.x, strength.x)
	for sp: Sprite2D in target.find_children("*", "Sprite2D", true, false):
		sp.material = mat
	var pulse := func(t: float) -> void:
		SpriteFx.set_glow(mat, color, lerpf(blur.x, blur.y, t), lerpf(strength.x, strength.y, t))
	var tw := create_tween().set_loops()
	tw.tween_method(pulse, 0.0, 1.0, half)
	tw.tween_method(pulse, 1.0, 0.0, half)

## -- wiring ---------------------------------------------------------------------------------------------------------

## Rebuilds the run-time wiring from the tree itself: the pieces the code reaches by name (`ui_piece`), the buttons
## (`ui_button`) and the bars (`ui_bar`). Runs on a tree built from json and on one instantiated from scenes/ui/.
func _wire_from_scene() -> void:
	_named.clear()
	_bars.clear()
	_collect(self)
	for piece in _bars:
		set_bar(piece, 1.0)   # a gauge starts full: the code slides it from there

func _collect(n: Node) -> void:
	for k in n.get_meta(&"ui_piece", []):
		var key := String(k)
		if not _named.has(key):
			_named[key] = n   # the first node claiming a name keeps it (a clip nested in several frames)
	if n.has_meta(&"ui_button"):
		_wire_button(n as Control, String(n.get_meta(&"ui_button")))
	if n.has_meta(&"ui_bar"):
		_wire_bar(n as Node2D)
	for c in n.get_children():
		_collect(c)

## Wires one button: its up / over / down art, the pad mark, the cursor and the click.
func _wire_button(b: Control, button_name: String) -> void:
	var states := {}
	for st in ["up", "over", "down"]:
		var art := b.get_node_or_null({"up": "Up", "over": "Over", "down": "Down"}[st])
		if art == null:
			return
		states[st] = art
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	PadNav.mark(b)
	@warning_ignore("shadowed_variable_base_class")
	var show := func(st: String):
		for k in states:
			states[k].visible = k == st
	b.mouse_entered.connect(show.bind("over"))
	b.mouse_exited.connect(show.bind("up"))
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			show.call("down" if e.pressed else "over")
			if not e.pressed:
				button_pressed.emit(button_name))

## Wires one bar holder (its ui_bar travel + its Clip / Content children) so set_bar() can slide it.
func _wire_bar(holder: Node2D) -> void:
	var data: Dictionary = holder.get_meta(&"ui_bar", {})
	var clip := holder.get_node_or_null("Clip") as Control
	var content := clip.get_node_or_null("Content") as Node2D
	if content == null:
		content = holder.find_child("Content", true, false) as Node2D   # moved out of the clip by hand
	if clip == null or content == null or data.is_empty():
		return
	_bars[_node_path(holder)] = {"clip": clip, "content": content, "full": data.full, "empty": data.empty}

## How set_bar() names a bar: its path under the layout root (a bar is a top-level node, so usually just its name).
func _node_path(n: Node) -> String:
	var parts := PackedStringArray()
	var c := n
	while c != null and c != self:
		parts.insert(0, String(c.name))
		c = c.get_parent()
	return "/".join(parts)

func _piece_keys(n: Node, keys: Array) -> void:
	n.set_meta(&"ui_piece", keys)

## Show frame `idx` (or the frame with label `idx`) of a frames piece.
func show_frame(piece: String, idx) -> void:
	var h: Node2D = _named.get(piece)
	if h == null:
		return
	if idx is String:
		idx = int(h.get_meta(&"labels", {}).get(idx, 0))
	for i in h.get_child_count():
		h.get_child(i).visible = i == idx

func set_bar(piece: String, ratio: float) -> void:
	var b: Dictionary = _bars.get(piece, {})
	if b.is_empty():
		return
	var p: Vector2 = b.empty.lerp(b.full, clampf(ratio, 0.0, 1.0))
	b.clip.position = p
	b.content.position = -p

# ------------------------------------------------------------------ builders

## One child Node2D per frame, only the shown frame visible. A frame is named after its label when it has one.
func _frames_node(frames: Array, labels: Dictionary, xf: Transform2D) -> Node2D:
	var holder := Node2D.new()
	holder.transform = xf
	var named := {}   # frame index -> label (a page per hero)
	for k in labels:
		named[int(labels[k])] = String(k)
	for i in frames.size():
		var fr := _leaves(frames[i], Transform2D.IDENTITY)
		fr.visible = false
		fr.name = String(named.get(i, "Frame%d" % i))
		holder.add_child(fr, true)
	if holder.get_child_count() > 0:
		holder.get_child(0).visible = true
	holder.set_meta(&"labels", labels)
	return holder

func _m(m: Array) -> Transform2D:
	return Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))

func _leaves(leaves: Array, xf: Transform2D) -> Node2D:
	var holder := Node2D.new()
	holder.transform = xf
	for lf in leaves:
		if lf[0] == "mask":
			holder.add_child(_masked(lf[1], lf[2]), true)
		elif lf[0] == "text":
			var l := _text({"m": lf[1], "name": lf[3] if lf.size() > 3 else null}.merged(lf[2]))
			l.set_meta(&"rec", lf[2])
			if lf.size() > 3 and lf[3] != null:
				l.name = String(lf[3])
			holder.add_child(l, true)
		elif _d.textures.has(lf[0]):
			holder.add_child(_sprite(lf), true)
	return holder

func _sprite(lf: Array) -> Sprite2D:
	var info: Dictionary = _d.textures[lf[0]]
	var sp := Sprite2D.new()
	sp.name = String(lf[0]).replace(":", "_")
	sp.centered = false
	sp.texture = load(info.res)
	sp.set_meta(&"tex_key", lf[0])
	var s := 1.0 / float(info.scale)
	var origin := Vector2(info.ox, info.oy)
	if lf.size() > 3 and lf[3] is Array:
		# one piece of the picture (a baked caption sheet cut into its captions by tools/fit_ui.gd)
		var r: Array = lf[3]
		sp.region_enabled = true
		sp.region_rect = Rect2(r[0], r[1], r[2], r[3])
		origin += Vector2(r[0], r[1]) * s
	sp.transform = _m(lf[1]) * Transform2D(Vector2(s, 0), Vector2(0, s), origin)
	if lf.size() > 2 and lf[2] != null:
		var ct: Array = lf[2]
		sp.modulate = Color(ct[0] + ct[4] / 255.0, ct[1] + ct[5] / 255.0, ct[2] + ct[6] / 255.0, clampf(ct[3] + ct[7] / 255.0, 0, 1))
	return sp

## Flash mask layer: the mask sprite clips its children (content re-expressed in the mask's space).
func _masked(mask: Array, content: Array) -> Node2D:
	var holder := Node2D.new()
	holder.name = "Art"
	for mk in mask:
		if not _d.textures.has(mk[0]):
			continue
		var m := _sprite(mk)
		m.modulate = Color.WHITE
		m.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		var inv := m.transform.affine_inverse()
		for lf in content:
			var c: Node2D = _masked(lf[1], lf[2]) if lf[0] == "mask" else (_sprite(lf) if _d.textures.has(lf[0]) else null)
			if c:
				c.transform = inv * c.transform
				m.add_child(c)
		holder.add_child(m)
	return holder

## How far a field's text is lifted from the top of its box: the middle of this font's glyphs is 0.55 em below the top
## of its line, the original's was about 0.51 em.
static func text_lift(font_size: float) -> float:
	return (INK_MIDDLE - 0.51) * font_size

func _text(n: Dictionary) -> Label:
	var l := Label.new()
	l.position = _m(n.m).origin + Vector2(n.b.x, n.b.y)
	l.size = Vector2(n.b.w, n.b.h)
	l.text = n.text
	l.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(n.align, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_size_override("font_size", int(n.size))
	# A field's text sits at the top of its box. This font's glyphs ride lower in their line than the original's did (its
	# line box is taller), so a field without a known frame is lifted by text_lift().
	var top := l.position.y
	l.position.y = top - text_lift(float(n.size))
	if n.has("fit"):
		# the frame this field sits in (found by tools/fit_ui.gd in the drawn art, fit = [top, bottom] relative to the
		# top of the field box): the middle of the glyphs goes to the middle of the frame, whatever the Flash box was. The
		# glyph middle of this font is INK_MIDDLE em below the top of its line (measured, at every size).
		var middle: float = top + (float(n.fit[0]) + float(n.fit[1])) / 2.0
		l.position.y = middle - INK_MIDDLE * float(n.size)
		l.size.y = float(n.size) * 1.6
	if n.has("nudge"):
		# a hand correction kept in the layout data (survives tools/fit_ui.gd): [dx, dy] px
		l.position += Vector2(float(n.nudge[0]), float(n.nudge[1]))
	l.add_theme_color_override("font_color", Color(n.color))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", int(n.get("outline", 2)))   # dark text on a light box: "outline": 0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Button: hit rect Control with its up / over / down art (the states are named so _wire_button() finds them again).
func _button(n: Dictionary) -> Control:
	var b := Control.new()
	var hit: Array = n.get("hit", [0, 0, 10, 10])
	var xf := _m(n.m)
	b.position = xf.origin + Vector2(hit[0], hit[1])
	b.size = Vector2(hit[2], hit[3])
	# a button whose states reuse one texture (only nudged down in the original) is brightened instead of jumping
	var same: bool = n.get("up", []).map(func(l): return [l[0], l[2] if l.size() > 2 else null]) == n.get("over", []).map(func(l): return [l[0], l[2] if l.size() > 2 else null])
	for st in ["up", "over", "down"]:
		var art := _leaves(n.get("up" if same and st == "over" else st, []), Transform2D(0.0, -Vector2(hit[0], hit[1])))
		if same and st == "over":
			art.modulate = Color(1.3, 1.15, 1.0)
		art.visible = st == "up"
		art.name = {"up": "Up", "over": "Over", "down": "Down"}[st]
		b.add_child(art, true)
	return b

## Bar = clip rect sliding between the original mask's empty and full positions; content stays put. The holder records
## its travel in `ui_bar` and names its two halves Clip / Content, which is all _wire_bar() needs.
func _bar(n: Dictionary) -> Node2D:
	var holder := Node2D.new()
	holder.transform = _m(n.m)
	var content := _leaves(n.content, Transform2D.IDENTITY)
	var cb := Rect2()
	for sp: Sprite2D in content.get_children():
		var r := sp.transform * Rect2(Vector2.ZERO, sp.texture.get_size())
		cb = r if cb.size == Vector2.ZERO else cb.merge(r)
	var a := Rect2(n.mask0[0], n.mask0[1], n.mask0[2], n.mask0[3])
	var b := Rect2(n.maskN[0], n.maskN[1], n.maskN[2], n.maskN[3])
	var a_full := a.intersection(cb).get_area() >= b.intersection(cb).get_area()
	var full := a if a_full else b
	var empty := b if a_full else a
	# unmasked layers of the gauge (its empty track) sit under the fill
	if n.other.size() > 0:
		var other := _leaves(n.other, Transform2D.IDENTITY)
		other.name = "Art"
		holder.add_child(other, true)
	var clip := Control.new()
	clip.name = "Clip"
	clip.clip_contents = true
	clip.size = full.size
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.name = "Content"
	clip.add_child(content, true)
	holder.add_child(clip, true)
	holder.set_meta(&"ui_bar", {"full": full.position, "empty": empty.position})
	return holder
