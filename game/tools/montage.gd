extends SceneTree
## Tile PNGs into one image: godot --headless -s res://tools/montage.gd -- <out.png> <cols> <a.png> <b.png> ...
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var cols := int(a[1])
	var files := a.slice(2)
	var w := 470
	var h := 295
	var rows := ceili(files.size() / float(cols))
	var m := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in files.size():
		var im := Image.load_from_file(files[i])
		im.convert(Image.FORMAT_RGBA8)
		im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		m.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	m.save_png(a[0])
	quit()
