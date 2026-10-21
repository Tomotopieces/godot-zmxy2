class_name UiLayout
extends Control
## A screen's layout: the hand-arranged editor scene scenes/ui/<name>.tscn. The nodes the code reaches are scene-unique
## names (%Name, "Access as Unique Name" in the editor): they can be moved anywhere in the scene, renaming one is what
## breaks its link. Every scene-unique button reports its click as button_pressed(<its node name>).

signal button_pressed(button_name: String)

static func create(ui_name: String) -> UiLayout:
	return load("res://scenes/ui/%s.tscn" % ui_name).instantiate()

func _ready() -> void:
	# the scene this layout is: its own file, or (main.tscn's title) the scene it is part of
	var scene: Node = self if scene_file_path != "" else owner
	var layer := get_parent()
	while layer != null and not layer is CanvasLayer:
		layer = layer.get_parent()
	var menu := layer != null and not layer is Hud
	if menu:
		PadFocus.screen(layer)
	for b: BaseButton in find_children("*", "BaseButton", true, false):
		if b.owner == scene and b.unique_name_in_owner:   # (buttons inside an instanced sub-scene belong to it)
			b.focus_mode = Control.FOCUS_ALL if menu else Control.FOCUS_NONE   # the pad reaches menu buttons
			if not b.has_theme_stylebox_override(&"focus"):
				b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())   # (PadFocus draws the highlight)
			b.pressed.connect(func():
				button_pressed.emit(String(b.name))
				Snd.ui())   # skipped when the handler already played one

## A scene-unique node of the layout.
func piece(node_name: String) -> Node:
	return get_node("%" + node_name)

func set_text(node_name: String, t: String) -> void:
	piece(node_name).text = t

## Pulsing outer glow on a picture: the original animates a GlowFilter's blur and strength up and back down (lit 无双
## logo, the next stage on the map). Rebuilt as a halo material of the sprites, pulsed by a tween.
func glow_pulse(target: Node, color: Color, blur: Vector2, strength: Vector2, half: float) -> void:
	var mat := SpriteFx.glow_material(color, blur.x, strength.x)
	for sp: Sprite2D in target.find_children("*", "Sprite2D", true, false) + ([target] if target is Sprite2D else []):
		sp.material = mat
	var pulse := func(t: float) -> void:
		SpriteFx.set_glow(mat, color, lerpf(blur.x, blur.y, t), lerpf(strength.x, strength.y, t))
	var tw := create_tween().set_loops()
	tw.tween_method(pulse, 0.0, 1.0, half)
	tw.tween_method(pulse, 1.0, 0.0, half)
