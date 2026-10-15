extends Node
## Stage U2, one-off migration: turns the attribute rows of the 背包 and 法宝 panels into StatRow nodes in their editor
## scenes, so the user can move and resize them by hand.
##   godot --headless --path game res://tools/ui_stat_rows_to_scene.tscn
## For res://scenes/ui/backpack.tscn and res://scenes/ui/sutra.tscn it rebuilds exactly the rows the panels used to build
## at run time (`Backpack._add_stat_rows()` / `SutraPanel._add_stat_rows()`, the STAT_COLS copied below): a StatRow
## (Caption + Box) per pair, at the same place, with the row's value Label moved into the box (it keeps its name and its
## `ui_piece` meta, so UiLayout._wire_from_scene() still wires it). It also
##   - deletes the backpack's baked caption sprites (backpack_v5:16) from the scene, and
##   - blanks the sutra's baked captions / boxes out of a copy of backpack_v5_470.png saved as
##     res://assets/ui/sutra/tex/backpack_v5_470_clean.png (the original PNG is left untouched).
## Refuses to run twice (a StatRow already in a scene): prints "already migrated".
## The cleaned texture has to be imported before it can be referenced, so on a checkout that does not have it yet the tool
## writes the PNG, prints the import command and stops:
##   godot --headless --path game --import      (once, after the tool wrote the PNG)
##   godot --headless --path game res://tools/ui_stat_rows_to_scene.tscn

const CLEAN_TEX := "res://assets/ui/sutra/tex/backpack_v5_470_clean.png"
const SUTRA_ART := "res://assets/ui/sutra/tex/backpack_v5_470.png"

## The backpack's two stacks of pairs (Backpack.STAT_COLS): x is the left of the captions, y the top of the first row.
const BACKPACK_COLS := [
	{"x": 115, "y": 293, "row_h": 30, "caption_w": 40, "box_w": 108,
		"rows": [{"caption": "生命", "label": "txt_hp"}, {"caption": "攻击", "label": "txt_att"},
			{"caption": "暴击", "label": "txt_baoji"}, {"caption": "回血", "label": "txt_hx"},
			{"caption": "经验", "label": "txt_exp", "box_w": 140}]},
	{"x": 275, "y": 293, "row_h": 30, "caption_w": 40, "box_w": 108,
		"rows": [{"caption": "魔法", "label": "txt_mp"}, {"caption": "防御", "label": "txt_def"},
			{"caption": "闪避", "label": "txt_sb"}, {"caption": "回蓝", "label": "txt_hl"}]},
]
## The sutra's three groups (SutraPanel.STAT_COLS).
const SUTRA_COLS := [
	{"x": 330, "y": 223, "row_h": 35, "caption_w": 40, "box_w": 80,
		"rows": [{"caption": "等级", "label": "txt_fbdj"}, {"caption": "成长", "label": "txt_fbczl"},
			{"caption": "五行", "label": "txt_fbwx"}]},
	{"x": 195, "y": 342, "row_h": 35, "caption_w": 40, "box_w": 80,
		"rows": [{"caption": "回血", "label": "txt_fbhx"}, {"caption": "攻击", "label": "txt_fbatk"},
			{"caption": "灵魂", "label": "txt_fblh", "box_w": 210}]},
	{"x": 324, "y": 342, "row_h": 35, "caption_w": 40, "box_w": 80,
		"rows": [{"caption": "回蓝", "label": "txt_fbhl"}, {"caption": "防御", "label": "txt_fbdef"}]},
]
## The baked captions / value boxes of the sutra, in the pixels of backpack_v5_470.png (SutraPanel.ERASE_RECTS).
const ERASE_RECTS := [Rect2i(252, 253, 262, 54), Rect2i(250, 326, 128, 50), Rect2i(252, 396, 262, 54),
	Rect2i(64, 490, 180, 122), Rect2i(321, 490, 180, 122), Rect2i(0, 624, 72, 46)]
## The texture leaf each scene's baked rows live in: backpack_v5:16 is hidden at run time, backpack_v5:470 blanked.
const BACKPACK_LEAF := "backpack_v5:16"
const SUTRA_LEAF := "backpack_v5:470"

func _ready() -> void:
	var scenes := {"backpack": BACKPACK_COLS, "sutra": SUTRA_COLS}
	var roots := {}
	for name in scenes:
		var path := "res://scenes/ui/%s.tscn" % name
		var ps := load(path) as PackedScene
		if ps == null:
			print("no %s" % path)
			get_tree().quit(1)
			return
		roots[name] = ps.instantiate()
		if _find_stat_row(roots[name]) != null:
			print("already migrated (%s holds a StatRow)" % path)
			_quit()
			return
	if not _clean_sutra_texture():
		get_tree().quit(1)   # the scenes are untouched: re-run this tool once the texture is imported
		return
	for name in scenes:
		_migrate(name, roots[name], scenes[name])
	_quit()

func _quit() -> void:
	get_tree().quit(0)

## Rewrites one scene: deletes / blanks its baked rows, then puts a StatRow per pair where `_add_stat_rows()` put them.
func _migrate(name: String, root: Node, cols: Array) -> void:
	var leaf: String = SUTRA_LEAF if name == "sutra" else BACKPACK_LEAF
	var sprites := _sprites_of(root, leaf)
	if name == "sutra":
		# the baked groups are blanked out of the cleaned copy of the texture, which all its leaves share
		var tex := load(CLEAN_TEX) as Texture2D
		for sp: Sprite2D in sprites:
			sp.texture = tex
	else:
		for sp: Sprite2D in sprites:   # the backpack's baked captions are whole sprites: delete them
			sp.get_parent().remove_child(sp)
			sp.free()
	var rows := Control.new()
	rows.name = "StatRows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the run-time rows went in right before the value labels (under their text, over the art)
	var at: int = (_find_piece(root, str(cols[0].rows[0].label)) as Node).get_index()
	root.add_child(rows)
	root.move_child(rows, at)
	rows.owner = root
	var extent := Vector2.ZERO
	for col: Dictionary in cols:
		for i in (col.rows as Array).size():
			var pair: Dictionary = col.rows[i]
			var value := _find_piece(root, str(pair.label)) as Label
			var row := StatRow.create_row(str(pair.caption), float(col.caption_w),
				float(pair.get("box_w", col.box_w)), value)
			row.name = "Row_" + str(pair.label)
			row.position = Vector2(float(col.x), float(col.y) + float(i) * float(col.row_h))
			rows.add_child(row)
			row.owner = root
			_own(row, root)
			extent = extent.max(row.position + row.size)
	rows.size = extent
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, "res://scenes/ui/%s.tscn" % name)
	print("res://scenes/ui/%s.tscn: %s (%d rows)" % [name, "saved" if err == OK else "ERROR %d" % err,
		(cols[0].rows as Array).size() + (cols[1].rows as Array).size() + ((cols[2].rows as Array).size() if cols.size() > 2 else 0)])

## Writes backpack_v5_470_clean.png (the ERASE_RECTS made transparent) for the sutra's texture leaves to use.
## The scenes are only rewritten once that PNG is imported, so a checkout that does not have it yet writes the PNG, stops
## here and prints the import command; the tool never runs Godot itself (an OS.execute() of the engine from inside it
## deadlocks).
func _clean_sutra_texture() -> bool:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SUTRA_ART))
	for r in ERASE_RECTS:
		img.fill_rect(r, Color(0, 0, 0, 0))
	img.save_png(ProjectSettings.globalize_path(CLEAN_TEX))
	if not FileAccess.file_exists(CLEAN_TEX + ".import"):
		print("%s written." % CLEAN_TEX)
		print("run `godot --headless --path game --import` first, then re-run")
		return false
	return true

func _sprites_of(root: Node, leaf: String) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for sp: Sprite2D in root.find_children("*", "Sprite2D", true, false):
		if sp.get_meta(&"tex_key", "") == leaf:
			out.append(sp)
	return out

func _find_stat_row(root: Node) -> Node:
	for n in root.find_children("*", "", true, false):
		if n is StatRow:
			return n
	return null

## The node the layout reaches with `piece` (its ui_piece meta), wherever it sits.
func _find_piece(root: Node, piece: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.get_meta(&"ui_piece", []).has(piece):
			return n
	return null

## Hands the row's nodes to the editor (owned by the scene root) so they get packed.
func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_own(c, root)
