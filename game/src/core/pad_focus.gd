class_name PadFocus
extends CanvasLayer
## Menus with the gamepad, on Godot's focus system: the screens' buttons and item icons take focus (FOCUS_ALL), the
## D-pad / left stick (ui_up / ui_down / ui_left / ui_right) move it, A (ui_accept) presses. This node adds what the
## focus system lacks here: the highlight while the pad is used, a first focus on the screen, focus kept on the screen
## on top (and inside its popup), and B, which closes the way Esc does.

const GROUP := &"pad_screen"   ## CanvasLayers that are menu screens (a UiLayout registers its layer; not the HUD)
const MODAL := &"pad_modal"    ## popups: while one is open only its controls can take focus

var _mark: Node2D
var _shown := false
var _spot := Vector2.INF       ## where the focus last was on a screen (not in a popup): it comes back there
var _mouse_down := false       ## a mouse button is held (a press in progress)

static func screen(layer: CanvasLayer) -> void:
	layer.add_to_group(GROUP)

static func modal(popup: Control) -> void:
	popup.add_to_group(MODAL)

## Item icons laid out in a grid (in tree, in reading order, `cols` per row): each one's focus neighbours are the cells
## next to it, so the pad walks the grid cell by cell (the edges are left to the focus system's own search).
static func link_grid(cells: Array, cols: int) -> void:
	for i in cells.size():
		var c: Control = cells[i]
		var at := func(j: int) -> NodePath: return c.get_path_to(cells[j])
		if i % cols > 0:
			c.focus_neighbor_left = at.call(i - 1)
		if i % cols < cols - 1 and i + 1 < cells.size():
			c.focus_neighbor_right = at.call(i + 1)
		if i >= cols:
			c.focus_neighbor_top = at.call(i - cols)
		if i + cols < cells.size():
			c.focus_neighbor_bottom = at.call(i + cols)

func _ready() -> void:
	layer = 99
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mark = Node2D.new()
	_mark.draw.connect(_draw_mark)
	_mark.visible = false
	add_child(_mark)

## The screen on top that has something to focus, or its open popup; null when no menu is up.
func _scope() -> Node:
	var top: CanvasLayer = null
	for l: CanvasLayer in get_tree().get_nodes_in_group(GROUP):
		if l.visible and (top == null or l.layer > top.layer) and not _targets(l).is_empty():
			top = l
	if top == null:
		return null
	for p: Control in get_tree().get_nodes_in_group(MODAL):
		if p.is_visible_in_tree() and top.is_ancestor_of(p) and not p.is_queued_for_deletion():
			return p
	return top

static func _targets(scope: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c: Control in scope.find_children("*", "Control", true, false):
		if c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree() and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		_mouse_down = e.pressed
	if e is InputEventMouseMotion:
		_hide()
		return
	if not (e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return
	var scope := _scope()
	if scope == null:
		return
	if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B:
		get_viewport().set_input_as_handled()
		if e.pressed:
			_cancel()
		return
	if not _shown and _is_nav(e):
		# the first press only shows where the focus is
		get_viewport().set_input_as_handled()
		_shown = true
		_mark.visible = true
		_keep_in(scope)

static func _is_nav(e: InputEvent) -> bool:
	for a in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept"]:
		if e.is_action_pressed(a):
			return true
	return false

func _process(_dt: float) -> void:
	var scope := _scope()
	var f := get_viewport().gui_get_focus_owner()
	if f != null and not _in_popup(f):
		_spot = f.get_global_rect().get_center()   # (before the fence below can take the focus away)
	_fence(scope)
	if scope == null:
		_hide()
		return
	if _shown:
		_keep_in(scope)
		_mark.queue_redraw()

## Only the top screen (or its open popup) can take focus: the focus system's own neighbour search would otherwise
## also reach the screens under it.
func _fence(scope: Node) -> void:
	for l: CanvasLayer in get_tree().get_nodes_in_group(GROUP):
		for c in l.get_children():
			if c is Control:
				var on: bool = (scope == l) if scope == null or not scope.is_in_group(MODAL) else (c == scope or c.is_ancestor_of(scope))
				(c as Control).focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED if on else Control.FOCUS_BEHAVIOR_DISABLED

func _in_popup(c: Control) -> bool:
	for p: Control in get_tree().get_nodes_in_group(MODAL):
		if p.is_ancestor_of(c):
			return true
	return false

## The focus stays on the top screen / its popup. When it is lost there (a popup closed, the screen refilled), it goes
## to the control nearest the spot it was on; in a popup it starts top-left.
func _keep_in(scope: Node) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f != null and scope.is_ancestor_of(f) and not f.is_queued_for_deletion() and (scope.is_in_group(MODAL) or not _in_popup(f)):
		return
	var popup := scope.is_in_group(MODAL)
	var best: Control = null
	var best_d := INF
	for c in _targets(scope):
		if not popup and _in_popup(c):
			continue
		var p := c.get_global_rect().get_center()
		var d := p.y * 2.0 + p.x if popup or _spot == Vector2.INF else p.distance_to(_spot)
		if d < best_d:
			best_d = d
			best = c
	if best != null:
		best.grab_focus()

## The mouse took over: no highlight and no focus (a clicked button would keep it), but the spot is remembered.
func _hide() -> void:
	var f := get_viewport().gui_get_focus_owner()
	# (a text field keeps it; and not while a mouse button is held: a button that loses focus mid-press drops the click)
	if (f is BaseButton or f is TextureRect) and not _mouse_down:
		get_viewport().gui_release_focus()
	_shown = false
	_mark.visible = false

func _cancel() -> void:
	# B closes the way Esc does: every screen closes on the pause action
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = &"pause"
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _draw_mark() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		return
	var r := f.get_global_rect().grow(3.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
	_mark.draw_rect(r, Color(1.0, 0.85, 0.2, 0.9), false, 3.0)
	_mark.draw_rect(r.grow(2.0), Color(1.0, 1.0, 1.0, 0.25 + 0.35 * pulse), false, 1.5)
