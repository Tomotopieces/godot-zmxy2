class_name UiLayout
extends Control
## Screen built from an original interface layout (assets/ui/<name>/ui.json, written by tools/rig/extract_ui.js).
## Node kinds: art (static sprites), frames (one visible frame), bar (clipped fill), text (Label), button.
## Named pieces are reachable with art(), frames(), text(), set_bar(); buttons emit `button_pressed`.

signal button_pressed(button_name: String)

var _d: Dictionary
var _named := {}     ## name -> Node (art / frames holder / Label / button Control)
var _bars := {}      ## name -> {clip, content, full: Vector2, empty: Vector2, glow}

static func create(ui_name: String) -> UiLayout:
	var u := UiLayout.new()
	u.build("res://assets/ui/%s/ui.json" % ui_name)
	return u

func build(path: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d = JSON.parse_string(FileAccess.get_file_as_string(path))
	for n in _d.nodes:
		var node: Node
		match n.type:
			"art":
				node = _leaves(n.leaves, _m(n.m))
			"frames":
				node = _frames_node(n.frames, n.get("labels", {}), _m(n.m))
				# clips nested in one of the frames, driven separately ("parent/child")
				for q in n.get("nested", []):
					var sub := _frames_node(q.frames, q.get("labels", {}), _m(q.m))
					node.get_child(int(q.frame)).add_child(sub)
					var key: String = "%s/%s" % [n.name, q.name]
					if not _named.has(key):
						_named[key] = sub
			"bar":
				node = _bar(n)
			"text":
				node = _text(n)
			"button":
				node = _button(n)
		if node == null:
			continue
		add_child(node)
		if n.name != null:
			_named[n.name] = node

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
## up and back down (lit 无双 logo, the next stage on the map). Rebuilt as a filter group with a looping tween.
func glow_pulse(target: Node2D, color: Color, blur: Vector2, strength: Vector2, half: float) -> void:
	var group := CanvasGroup.new()
	group.fit_margin = blur.y + 4.0
	group.clear_margin = Rig.filter_clear_margin(group.fit_margin)
	group.use_mipmaps = false
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/rig/flash_filter.gdshader")
	mat.set_shader_parameter("glow_on", true)
	mat.set_shader_parameter("glow_color", color)
	group.material = mat
	for c in target.get_children():
		c.reparent(group, false)
	target.add_child(group)
	var pulse := func(t: float) -> void:
		var b := lerpf(blur.x, blur.y, t)
		mat.set_shader_parameter("glow_blur", Vector2(b, b))
		mat.set_shader_parameter("glow_strength", lerpf(strength.x, strength.y, t))
	var tw := create_tween().set_loops()
	tw.tween_method(pulse, 0.0, 1.0, half)
	tw.tween_method(pulse, 1.0, 0.0, half)

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

## One child Node2D per frame, only the shown frame visible.
func _frames_node(frames: Array, labels: Dictionary, xf: Transform2D) -> Node2D:
	var holder := Node2D.new()
	holder.transform = xf
	for f in frames:
		var fr := _leaves(f, Transform2D.IDENTITY)
		fr.visible = false
		holder.add_child(fr)
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
			holder.add_child(_masked(lf[1], lf[2]))
		elif lf[0] == "text":
			var l := _text({"m": lf[1], "name": lf[3] if lf.size() > 3 else null}.merged(lf[2]))
			if lf.size() > 3 and lf[3] != null:
				l.name = String(lf[3])
			holder.add_child(l)
		elif _d.textures.has(lf[0]):
			holder.add_child(_sprite(lf))
	return holder

func _sprite(lf: Array) -> Sprite2D:
	var info: Dictionary = _d.textures[lf[0]]
	var sp := Sprite2D.new()
	sp.centered = false
	sp.texture = load(info.res)
	var s := 1.0 / float(info.scale)
	sp.transform = _m(lf[1]) * Transform2D(Vector2(s, 0), Vector2(0, s), Vector2(info.ox, info.oy))
	if lf.size() > 2 and lf[2] != null:
		var ct: Array = lf[2]
		sp.modulate = Color(ct[0] + ct[4] / 255.0, ct[1] + ct[5] / 255.0, ct[2] + ct[6] / 255.0, clampf(ct[3] + ct[7] / 255.0, 0, 1))
	if info.has("label"):
		sp.add_child(_lettering(info.label))
	return sp

## Real text in place of lettering that the original draws as a bitmap (tools/rig/ui_text.js). Lives in the texture's
## own pixel space, so it scales, hides and tints with the sprite.
func _lettering(d: Dictionary) -> Label:
	var l := Label.new()
	var box: Array = d.box
	l.text = d.text
	l.position = Vector2(box[0], box[1])
	l.size = Vector2(box[2], box[3])
	l.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(d.align, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sz := int(d.size)
	if sz <= 0:
		var font := l.get_theme_default_font()
		sz = int(box[3] * 0.9)
		while sz > 6 and font.get_string_size(d.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > box[2]:
			sz -= 1
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(d.color))
	l.add_theme_color_override("font_outline_color", Color(d.outline))
	l.add_theme_constant_override("outline_size", int(d.outline_size))
	if d.bold:
		l.add_theme_font_override("font", preload("res://assets/fonts/LXGWWenKai-Medium.ttf"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Flash mask layer: the mask sprite clips its children (content re-expressed in the mask's space).
func _masked(mask: Array, content: Array) -> Node2D:
	var holder := Node2D.new()
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

func _text(n: Dictionary) -> Label:
	var l := Label.new()
	l.position = _m(n.m).origin + Vector2(n.b.x, n.b.y)
	l.size = Vector2(n.b.w, n.b.h)
	l.text = n.text
	l.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(n.align, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_size_override("font_size", int(n.size))
	l.add_theme_color_override("font_color", Color(n.color))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Button: hit rect Control with up / over / down art.
func _button(n: Dictionary) -> Control:
	var b := Control.new()
	var hit: Array = n.get("hit", [0, 0, 10, 10])
	var xf := _m(n.m)
	b.position = xf.origin + Vector2(hit[0], hit[1])
	b.size = Vector2(hit[2], hit[3])
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var states := {}
	# a button whose states reuse one texture (only nudged down in the original) is brightened instead of jumping
	var same: bool = n.get("up", []).map(func(l): return l[0]) == n.get("over", []).map(func(l): return l[0])
	for st in ["up", "over", "down"]:
		var art := _leaves(n.get("up" if same and st == "over" else st, []), Transform2D(0.0, -Vector2(hit[0], hit[1])))
		if same and st == "over":
			art.modulate = Color(1.3, 1.15, 1.0)
		art.visible = st == "up"
		b.add_child(art)
		states[st] = art
	var show := func(st: String):
		for k in states:
			states[k].visible = k == st
	b.mouse_entered.connect(show.bind("over"))
	b.mouse_exited.connect(show.bind("up"))
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			show.call("down" if e.pressed else "over")
			if not e.pressed:
				button_pressed.emit(n.name))
	return b

## Bar = clip rect sliding between the original mask's empty and full positions; content stays put.
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
		holder.add_child(_leaves(n.other, Transform2D.IDENTITY))
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = full.size
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(content)
	holder.add_child(clip)
	_bars[n.name] = {"clip": clip, "content": content, "full": full.position, "empty": empty.position}
	set_bar(n.name, 1.0)
	return holder
