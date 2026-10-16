extends Node
## Renders the bag picture (assets/items/fall_<id>.png) of equipment that has no ground picture in the original, from the
## art the game already shows for it: a weapon or wing as the hero holds / wears it (the rig's equipment slot), a
## fashion on the bag portrait, a treasure as it follows the hero. Run once after changing such art:
##   godot --path game --position 6000,6000 res://tools/render_item_art.tscn
## (non-headless: it renders through a SubViewport).

const SIZE := 96            ## px of the saved picture (shown at about 38 px in a cell)
const MARGIN := 4.0

## id -> [kind, what]: "scene" = a PackedScene path, "portrait" = [role rig, cloth variant], "rig" = [rig, action]
## Items without art anywhere but their framed icon (rings, consumables, stones) keep the picture cut out of that icon.
const ITEMS := {
	"nyd": ["scene", "res://assets/rigs/wukong/slots/slot185_8.tscn"],
	"myz": ["scene", "res://assets/rigs/tangseng/slots/slot862_8.tscn"],
	"syc": ["scene", "res://assets/rigs/bajie/slots/slot30_6.tscn"],
	"ttzy": ["scene", "res://assets/rigs/wukong/slots/slot116_3.tscn"],
	"wds": ["rig", ["fabao_wds", "walk"]],
	"wkmrz": ["portrait", ["bag_wukong", 7]], "tsmrz": ["portrait", ["bag_tangseng", 7]], "bjmrz": ["portrait", ["bag_bajie", 7]],
	"wkwdg": ["portrait", ["bag_wukong", 8]], "tswdg": ["portrait", ["bag_tangseng", 8]], "bjwdg": ["portrait", ["bag_bajie", 8]],
	"wkbsz": ["portrait", ["bag_wukong", 9]], "tsbsz": ["portrait", ["bag_tangseng", 9]], "bjbsz": ["portrait", ["bag_bajie", 9]],
	"wkzyf": ["portrait", ["bag_wukong", 10]], "tszyf": ["portrait", ["bag_tangseng", 10]], "bjzyf": ["portrait", ["bag_bajie", 10]],
	"jwkwdg": ["portrait", ["bag_wukong", 11]], "jtswdg": ["portrait", ["bag_tangseng", 11]], "jbjwdg": ["portrait", ["bag_bajie", 11]],
	"jwkzyf": ["portrait", ["bag_wukong", 12]], "jtszyf": ["portrait", ["bag_tangseng", 12]], "jbjzyf": ["portrait", ["bag_bajie", 12]],
}

func _ready() -> void:
	get_tree().create_timer(120.0, true, false, true).timeout.connect(get_tree().quit.bind(2))
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	for id in ITEMS:
		var e: Array = ITEMS[id]
		var holder := Node2D.new()
		vp.add_child(holder)
		var art: Node2D
		match e[0]:
			"scene":
				art = (load(e[1]) as PackedScene).instantiate()
			"rig", "portrait":
				art = Rig.create(e[1][0])
		holder.add_child(art)
		if e[0] == "rig":
			(art as Rig).play(StringName(e[1][1]))
		elif e[0] == "portrait":
			(art as Rig).play((art as Rig).actions[0])
			(art as Rig).set_equip("cloth", int(e[1][1]))
		await get_tree().process_frame
		await get_tree().process_frame
		for ap: AnimationPlayer in art.find_children("*", "AnimationPlayer", true, false):
			ap.pause()   # frame 0: a still picture
		var box := _bounds(art)
		if box.size.x <= 0.0:
			push_error("render_item_art: %s shows nothing" % id)
			holder.queue_free()
			continue
		var k := (SIZE - 2.0 * MARGIN) / maxf(box.size.x, box.size.y)
		holder.scale = Vector2(k, k)
		holder.position = Vector2(SIZE, SIZE) / 2.0 - box.get_center() * k
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://assets/items/fall_%s.png" % id))
		print("rendered ", id, " box ", box)
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()

## The visible pictures' rectangle in the holder's space.
func _bounds(n: Node2D) -> Rect2:
	var box := Rect2()
	var first := true
	var inv := (n.get_parent() as Node2D).global_transform.affine_inverse()
	for sp: Sprite2D in n.find_children("*", "Sprite2D", true, false):
		if not sp.is_visible_in_tree() or sp.texture == null:
			continue
		var r := sp.get_rect()
		var xf := inv * sp.global_transform
		for c in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
			var p: Vector2 = xf * c
			if first:
				box = Rect2(p, Vector2.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box
