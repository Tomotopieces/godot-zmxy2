extends Node
## Bag and skill shop of a hero: godot --path game --position 6000,6000 res://tools/role_ui_shot.tscn -- <role> <out prefix>
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	print("start ", a)
	GameState.new_game(a[0])
	GameState.souls = 3000
	for id in ["ptxzg"]:
		GameState.add_to_bag(GameState.make_item(id))
	for it in EquipmentCatalog.get_catalog().items.values():
		if it.user == GameState.hero_data.character and it.type in [&"weapon", &"cloth"]:
			GameState.add_to_bag(GameState.make_item(String(it.id)), true)
	var ps := PlayScreen.create(Vector2i(1, 1))
	add_child(ps)
	await get_tree().create_timer(0.6, false).timeout
	for i in 3:
		GameState.wear(GameState.tab_items("equip")[0])
	ps._open_bag()
	await get_tree().create_timer(0.5, true).timeout
	get_viewport().get_texture().get_image().save_png(a[1] + "_bag.png")
	ps._bag.close()
	await get_tree().create_timer(0.2, true).timeout
	var s := SkillShop.new()
	ps.add_child(s)
	await get_tree().create_timer(0.5, true).timeout
	get_viewport().get_texture().get_image().save_png(a[1] + "_shop.png")
	get_tree().quit()
