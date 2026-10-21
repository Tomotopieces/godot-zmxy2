class_name UiLayout
extends Control
## A screen made from an original interface layout: the editor scene scenes/ui/<name>.tscn, arranged by hand.
## Every node the code reaches carries its piece names in the meta `ui_piece`, a button its name in `ui_button`;
## _wire_from_scene() walks the tree and wires those. A gauge is a holder with a "Fill" TextureProgressBar.

signal button_pressed(button_name: String)

const INK_MIDDLE := 0.55   ## where the middle of this font's glyphs lies below the top of the line, in em

var _named := {}     ## name -> Node (art / frames holder / Label / button Control)

## Wired on creation, so texts and visibility can be set before the layout is added to the tree.
static func create(ui_name: String) -> UiLayout:
	var u: UiLayout = load("res://scenes/ui/%s.tscn" % ui_name).instantiate()
	u._wire_from_scene()
	return u

func _ready() -> void:
	if _named.is_empty():   # instanced directly in another scene (main.tscn's title)
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
## (`ui_button`).
func _wire_from_scene() -> void:
	_named.clear()
	_collect(self)

func _collect(n: Node) -> void:
	for k in n.get_meta(&"ui_piece", []):
		var key := String(k)
		if not _named.has(key):
			_named[key] = n   # the first node claiming a name keeps it (a clip nested in several frames)
	if n.has_meta(&"ui_button"):
		_wire_button(n as BaseButton, String(n.get_meta(&"ui_button")))
	for c in n.get_children():
		_collect(c)

## Wires one button (a Button: its normal / hover / pressed styles are its art): the pad mark and the click.
func _wire_button(b: BaseButton, button_name: String) -> void:
	PadNav.mark(b)
	b.pressed.connect(func():
		button_pressed.emit(button_name)
		Snd.ui())   # skipped when the handler already played one


## Show frame `idx` (or the frame with label `idx`) of a frames piece.
func show_frame(piece: String, idx) -> void:
	var h: Node2D = _named.get(piece)
	if h == null:
		return
	if idx is String:
		idx = int(h.get_meta(&"labels", {}).get(idx, 0))
	for i in h.get_child_count():
		h.get_child(i).visible = i == idx

## A gauge (its "Fill" TextureProgressBar) shows `ratio` (0..1).
func set_bar(piece: String, ratio: float) -> void:
	var n := get_piece(piece)
	if n != null:
		(n.get_node("Fill") as TextureProgressBar).value = clampf(ratio, 0.0, 1.0)
