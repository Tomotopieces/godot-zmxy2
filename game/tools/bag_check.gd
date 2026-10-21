extends Node
## Check of the backpack and item rules: gives test gear, wears some, uses items, revives; optional screenshots.
##   godot --headless --path game res://tools/bag_check.tscn
##   godot --path game res://tools/bag_check.tscn -- --out=<dir>     (screenshots)

var _out := ""
var _fails := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	GameState.new_game()
	var main: Node = PlayScreen.create(Vector2i(1, 1))
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	for id in main.TEST_GEAR:
		GameState.add_to_bag(GameState.make_item(id))
	_check("stones stack", GameState.count_of("wpqhs1") == 2 and GameState.tab_items("item").size() == 6)
	_check("unique charm", not GameState.add_to_bag(GameState.make_item("csgs")))
	for id in ["tsyj", "bsxj", "csgs", "wkzyf", "xtzy"]:
		_check("wear " + id, GameState.wear(_find(id)))
	var look := GameState.appearance()
	_check("fashion look", look.cloth == 10 and look.wing == 2)
	_check("fashion drop bonus", is_equal_approx(GameState.drop_mul(), 1.2))
	print("worn atk=%d def=%d hp=%d look=%s bag=%d" % [GameState.attack_power(), GameState.defense(), GameState.max_hp(), look, GameState.bag.size()])
	# buffs
	var hp0 := GameState.max_hp()
	GameState.use_item(_find("jxbuff"))
	GameState.use_item(_find("sbbl"))
	GameState.use_item(_find("hhbuff"))
	_check("hp buff", GameState.max_hp() == int(hp0 * 1.5))
	_check("drop buff", is_equal_approx(GameState.drop_mul(), 2.4))
	_check("mp regen buff", GameState.mp_regen() == 10)
	_check("items used up", GameState.tab_items("item").size() == 3)
	_check("unusable item", GameState.use_item(_find("yll")) == "" and GameState.has_item("yll"))
	# save / load keeps buffs and worn slots
	var saved: Dictionary = GameState._to_dict()
	_check("save has buffs", saved.buffs.size() == 3 and saved.worn.fashion.id == "wkzyf")
	await get_tree().create_timer(0.3).timeout
	_shot("bag_game")
	# revive
	var h: Hero = main.level.hero
	h.lose_hp(999999)
	_check("revived", h.is_alive() and h.hp == int(h.max_hp * 0.5) and GameState.worn[&"accessory"] == null)
	h.lose_hp(999999)
	_check("dies without charm", not h.is_alive())
	main._over = false
	main._open_bag()
	await get_tree().create_timer(0.3).timeout
	var bag: Backpack = main._bag
	_shot("bag_equip")
	for tab in ["BtnDaoJu", "BtnShiZhuang"]:
		bag.show_tab(tab)
		await get_tree().create_timer(0.2).timeout
		var first: Control = bag._grid.get_children().filter(func(c): return c is TextureRect)[0]
		bag._on_bag_click(first, GameState.tab_items(Backpack.TABS[tab])[0])
		await get_tree().create_timer(0.2).timeout
		_shot("bag_" + tab)
	print("BAG CHECK %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(1 if _fails else 0)

func _find(id: String) -> int:
	return GameState.bag.find_custom(func(i): return i.id == id)

func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])

func _shot(n: String) -> void:
	if _out != "":
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, n])
