class_name ComboCounter
extends Node2D
## The combo counter of the original (export.Batter): the COMBO title plus one Sprite2D per digit of the
## count. show_count() rebuilds the digits, pops each one from digit_scale_start to digit_scale_end over
## pop_time (the extracted art is the clip's first, biggest frame) and fades the whole counter out over
## fade_time. Replaces the 11 generated scenes assets/ui/combo, combo_num0..9 built at run time by
## hud.show_combo(); the numbers of the original are kept.

@export var digit_textures: Array[Texture2D] = []   ## index 0..9, the extracted combo_num art
@export var digit_spacing := 50.0
@export var digit_y := 28.3
@export var x_for_1_digit := 4.0
@export var x_for_2_digits := -44.6
@export var x_for_3_digits := -95.6
@export var digit_scale_start := 1.0
@export var digit_scale_end := 1.4 / 3.5
@export var pop_time := 4.0 / 24.0
@export var fade_time := 3.5
## One digit inside its slot (the Sprite2D transform of combo_num0.tscn: ox/oy -35 at scale 2.5 on art scaled 1/2).
@export var digit_sprite_transform := Transform2D(Vector2(1.25, 0.0), Vector2(0.0, 1.25), Vector2(-87.5, -87.5))

@onready var _digits: Node2D = $Digits

var _tween: Tween

func show_count(count: int) -> void:
	if count < 2:
		return
	for c in _digits.get_children():
		_digits.remove_child(c)
		c.queue_free()
	var text := str(count)
	var x := x_for_1_digit if count < 10 else (x_for_2_digits if count < 100 else x_for_3_digits)
	for i in text.length():
		var s := Sprite2D.new()
		s.centered = false
		s.texture = digit_textures[int(text[i])]
		s.transform = Transform2D(0.0, Vector2(x + i * digit_spacing, digit_y)) * digit_sprite_transform
		s.scale = s.scale * digit_scale_start
		s.name = "Digit%d" % (i + 1)
		_digits.add_child(s)
		s.create_tween().tween_property(s, "scale", Vector2.ONE * (digit_sprite_transform.get_scale().x * digit_scale_end), pop_time)
	modulate.a = 1.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
