extends Node2D
## Screenshot one extracted UI layout: godot --path game res://tools/ui_shot.tscn -- <ui name> <out.png>
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.3, 0.35)
	bg.size = Vector2(940, 590)
	add_child(bg)
	add_child(UiLayout.create(a[0]))
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a[1])
	get_tree().quit()
