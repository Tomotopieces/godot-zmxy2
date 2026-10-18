class_name PadNav
extends CanvasLayer
## Gamepad navigation of every menu screen. Controls that can be clicked register with PadNav.mark(); while any is on
## screen (and not part of the HUD), the D-pad / left stick moves a highlight between them (nearest in that direction),
## A clicks, B / Back closes (as Esc does). The click is the real thing: the same mouse events the control already
## handles, and hovering fires its mouse_entered / mouse_exited, so tooltips and hover art work unchanged.
## While a menu is up the pad's game buttons are swallowed, so nothing is attacked behind it.

const GROUP := &"pad_focus"
const META_SEQ := &"pad_seq"
const META_MODAL := &"pad_modal"
const STICK_DEADZONE := 0.55
const REPEAT_FIRST := 0.35
const REPEAT_EVERY := 0.12

static var _seq := 0

var _focus: Control
var _last_center := Vector2.ZERO
var _modal_return := Vector2.ZERO   ## where the highlight was when a popup took it: it goes back there when the popup closes
var _cursor: Node2D
var _dir := Vector2i.ZERO        ## held direction (stick)
var _repeat := 0.0
var _shown := false

## Makes a control reachable with the pad.
static func mark(c: Control) -> void:
	_seq += 1
	c.set_meta(META_SEQ, _seq)
	c.add_to_group(GROUP)

## A popup: while it is on screen only its controls can be reached.
static func modal(root: Node) -> void:
	root.set_meta(META_MODAL, true)

func _ready() -> void:
	layer = 99
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cursor = Node2D.new()
	_cursor.draw.connect(_draw_cursor)
	_cursor.visible = false
	add_child(_cursor)

# ------------------------------------------------------------------ what can be reached now

func _layer_of(c: Control) -> CanvasLayer:
	var n := c.get_parent()
	while n != null and not n is CanvasLayer:
		n = n.get_parent()
	return n as CanvasLayer

func _modal_of(c: Control) -> Node:
	var n: Node = c
	var found: Node = null
	while n != null:
		if n.has_meta(META_MODAL):
			found = n
		n = n.get_parent()
	return found

func _candidates() -> Array[Control]:
	var out: Array[Control] = []
	var top := -1000
	for n in get_tree().get_nodes_in_group(GROUP):
		var c := n as Control
		if c == null or c.is_queued_for_deletion() or not c.is_visible_in_tree() or c.size.x < 2.0 or c.size.y < 2.0:
			continue
		var l := _layer_of(c)
		if l == null or l is Hud or l == self:
			continue
		if l.layer > top:
			top = l.layer
			out.clear()
		if l.layer == top:
			out.append(c)
	# a popup on that layer hides the controls behind it
	var modal: Node = null
	var best := -1
	for c in out:
		var m := _modal_of(c)
		if m != null and int(c.get_meta(META_SEQ, 0)) > best:
			best = int(c.get_meta(META_SEQ, 0))
			modal = m
	if modal != null:
		out = out.filter(func(c: Control) -> bool: return modal.is_ancestor_of(c))
	return out

func active() -> bool:
	return not _candidates().is_empty()

# ------------------------------------------------------------------ input

func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_hide()
		return
	if not (e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return
	var cands := _candidates()
	if cands.is_empty():
		_hide()
		return
	if e is InputEventJoypadMotion:
		if e.axis == JOY_AXIS_LEFT_X or e.axis == JOY_AXIS_LEFT_Y:
			get_viewport().set_input_as_handled()
		return   # the stick is read each frame
	var b := e as InputEventJoypadButton
	match b.button_index:
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if b.pressed:
				_step({JOY_BUTTON_DPAD_UP: Vector2i.UP, JOY_BUTTON_DPAD_DOWN: Vector2i.DOWN,
					JOY_BUTTON_DPAD_LEFT: Vector2i.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2i.RIGHT}[b.button_index], cands)
		JOY_BUTTON_A:
			# on release: the press must not still be held when the next screen (a stage) starts, or it would be a jump
			if not b.pressed:
				_activate(cands)
		JOY_BUTTON_B:
			if b.pressed:
				_cancel()
		JOY_BUTTON_START, JOY_BUTTON_BACK:
			return   # the screens close themselves on these (pause / open_bag)
		_:
			pass   # swallowed: no attacking behind a menu
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var cands := _candidates()
	if cands.is_empty():
		_hide()
		_last_center = Vector2.ZERO
		_modal_return = Vector2.ZERO
		_dir = Vector2i.ZERO
		return
	if _focus != null and (not is_instance_valid(_focus) or not cands.has(_focus)):
		# a popup opened: remember the control that opened it; otherwise another screen starts from its first control
		# (a popup closing goes back to that spot in _pick_start)
		if is_instance_valid(_focus) and _modal_of(_focus) == null and _modal_of(cands[0]) != null:
			_modal_return = _center(_focus)
		elif _modal_return == Vector2.ZERO or not is_instance_valid(_focus) or _modal_of(_focus) == null:
			_last_center = Vector2.ZERO
		_lose(false)
	if _shown and _focus == null:
		_pick_start(cands)
	# the left stick as a repeating direction
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var d := Vector2i.ZERO
	if v.length() > STICK_DEADZONE:
		d = Vector2i(signi(roundi(v.x)), 0) if absf(v.x) > absf(v.y) else Vector2i(0, signi(roundi(v.y)))
	if d == Vector2i.ZERO:
		_dir = d
		_repeat = 0.0
	elif d != _dir:
		_dir = d
		_repeat = REPEAT_FIRST
		_step(d, cands)
	else:
		_repeat -= delta
		if _repeat <= 0.0:
			_repeat = REPEAT_EVERY
			_step(d, cands)
	if _focus != null:
		_cursor.queue_redraw()

# ------------------------------------------------------------------ moving the highlight

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func _pick_start(cands: Array[Control]) -> void:
	# a popup has closed: back to the control that opened it (a sold item's cell, even when the next item moves in)
	if _modal_return != Vector2.ZERO and cands.all(func(c: Control) -> bool: return _modal_of(c) == null):
		_last_center = _modal_return
		_modal_return = Vector2.ZERO
	var best: Control = null
	for c in cands:
		if best == null or _score_start(c) < _score_start(best):
			best = c
	_gain(best)

## Start at the control nearest the last highlighted spot, else the top-left one.
func _score_start(c: Control) -> float:
	var p := _center(c)
	return p.distance_to(_last_center) if _last_center != Vector2.ZERO else p.y * 2.0 + p.x

func _step(dir: Vector2i, cands: Array[Control]) -> void:
	_shown = true
	if _focus == null or not is_instance_valid(_focus):
		_pick_start(cands)
		return
	var from := _center(_focus)
	var best: Control = null
	var best_score := INF
	for c in cands:
		if c == _focus:
			continue
		var to := _center(c) - from
		var along := to.x * dir.x + to.y * dir.y
		if along <= 1.0:
			continue
		var across := absf(to.x * dir.y) + absf(to.y * dir.x)
		var score := along + across * 2.0
		if score < best_score:
			best_score = score
			best = c
	if best != null:
		_gain(best)

func _gain(c: Control) -> void:
	_lose(true)
	_focus = c
	_last_center = _center(c)
	_shown = true
	_cursor.visible = true
	c.mouse_entered.emit()
	_cursor.queue_redraw()

func _lose(hover_out: bool) -> void:
	if _focus != null and is_instance_valid(_focus) and hover_out:
		_focus.mouse_exited.emit()
	_focus = null

func _hide() -> void:
	if _focus != null:
		_lose(true)
	_shown = false
	if _cursor:
		_cursor.visible = false

# ------------------------------------------------------------------ acting

func _activate(cands: Array[Control]) -> void:
	if _focus == null or not is_instance_valid(_focus) or not cands.has(_focus):
		_shown = true
		_pick_start(cands)
		return
	var c := _focus
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = c.size / 2.0
		ev.global_position = c.get_global_rect().get_center()
		c.gui_input.emit(ev)
		if not is_instance_valid(c):
			break

func _cancel() -> void:
	# B closes the way Esc does: every screen closes on the pause action
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = &"pause"
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _draw_cursor() -> void:
	if _focus == null or not is_instance_valid(_focus):
		return
	var r := _focus.get_global_rect().grow(3.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
	_cursor.draw_rect(r, Color(1.0, 0.85, 0.2, 0.9), false, 3.0)
	_cursor.draw_rect(r.grow(2.0), Color(1.0, 1.0, 1.0, 0.25 + 0.35 * pulse), false, 1.5)
