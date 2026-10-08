class_name Cartoon
extends CanvasLayer
## Story comic (export.cartoon.GameCartoon): full-screen pages, click to turn.
## "开场" = 3 opening pages, "红孩儿副本" = 1 page before 6-1, "通关" = ending.

signal finished

const PAGES := "res://assets/ui/cartoon/pages.json"
const SEQUENCES := {"开场": [0, 1, 2], "红孩儿副本": [3], "通关": [4]}

var sequence := "开场"
var _pages: Array = []
var _index := 0
var _holder: Node2D

static func create(seq: String) -> Cartoon:
	var c := Cartoon.new()
	c.sequence = seq
	return c

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pages = JSON.parse_string(FileAccess.get_file_as_string(PAGES)).pages
	_holder = Node2D.new()
	add_child(_holder)
	_show()

func _show() -> void:
	for c in _holder.get_children():
		c.queue_free()
	for lf in _pages[SEQUENCES[sequence][_index]]:
		var sp := Sprite2D.new()
		sp.centered = false
		sp.texture = load(lf.tex)
		var s := 1.0 / float(lf.scale)
		var m: Array = lf.m
		sp.transform = Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5])) \
			* Transform2D(Vector2(s, 0), Vector2(0, s), Vector2(lf.ox, lf.oy))
		_holder.add_child(sp)

func _input(e: InputEvent) -> void:
	var click: bool = e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT
	if not (click or e.is_action_pressed("attack") or e.is_action_pressed("jump") or e.is_action_pressed("ui_accept")):
		return
	get_viewport().set_input_as_handled()
	_index += 1
	if _index >= SEQUENCES[sequence].size():
		finished.emit()
		queue_free()
	else:
		_show()
