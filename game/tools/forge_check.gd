extends Node
## Check of the 炼丹炉 / 法宝 / 商城 rules and screens.
##   godot --headless --path game res://tools/forge_check.tscn
##   godot --path game res://tools/forge_check.tscn -- --out=<dir>     (screenshots)

var _out := ""
var _fails := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	GameState.new_game()
	GameState.souls = 100000
	# strengthening chances (Strength.changeLuck)
	var sword := GameState.make_item("tsyj")
	var s1 := GameState.make_item("wpqhs1")
	var s4 := GameState.make_item("wpqhs4")
	_check("1 stone at +0", is_equal_approx(Forge.success_chance(sword, [s1], false), 0.375))
	_check("2 stones + luck", is_equal_approx(Forge.success_chance(sword, [s1, s1], true), 0.9375))
	_check("capped at 1", Forge.success_chance(sword, [s4, s4], true) == 1.0)
	sword.plus = 7
	_check("no chance at +7", Forge.success_chance(sword, [s4, s4, s4], true) == 0.0)
	sword.plus = 3
	Rng.seed_with(1)
	var lost := 0
	for i in 50:
		var e := sword.copy()
		if not Forge.strengthen(e, [s1], false, false) and e.plus == 2:
			lost += 1
	_check("failure at +3 drops a level", lost > 40)
	var kept := sword.copy()
	Forge.strengthen(kept, [GameState.make_item("wpqhs5")], false, true)
	_check("keep charm", kept.plus == 3)
	sword.plus = 2
	var base_atk := float(sword.stats.atk)
	GameState.add_to_bag(sword)
	GameState.wear(0)
	_check("strengthened stats", is_equal_approx(GameState.bonus("atk"), base_atk + 2 * EquipmentCatalog.find("tsyj").strengthen.atk))
	# fusion
	var mats := [GameState.make_item("dslj"), GameState.make_item("dsqz"), GameState.make_item("dsyj")]
	var r := Forge.recipe_for(mats)
	_check("recipe any order", r.get("out", "") == "dshl" and Forge.fusion_cost(r) == 1000)
	var hulu := Forge.produce(r, mats)
	_check("treasure made", hulu.lv == 1 and hulu.growth >= 0.5 and hulu.growth <= 1.0 and not hulu.elem.is_empty())
	var hp0 := float(hulu.stats.get("hp", 0.0))
	Forge.upgrade(hulu)
	_check("treasure level up", hulu.lv == 2 and hulu.stats.hp >= hp0 + floorf(20 * hulu.growth))
	_check("upgrade cost", Forge.upgrade_cost(hulu) == 4000 and Forge.skill_cost(hulu) == 50)
	var wds := Forge.produce(Forge.recipe_for([GameState.make_item("mzyj"), GameState.make_item("szyj"), GameState.make_item("dcyj")]), [])
	_check("五毒兽 fixed stats + passive", wds.stats.atk == 50.0 and wds.stats.size() == 5 and wds.lv == 1)
	var st := Forge.recipe_for([s1, s1, s1])
	_check("stone recipe free 75%", st.out == "wpqhs2" and Forge.fusion_cost(st) == 0 and is_equal_approx(Forge.fusion_chance(st), 0.75))
	# 地藏金戒: the 地藏戒 adds what it has (strengthening included); 贪 / 嗔 are rolled when melted (the bag shows no numbers for them)
	var dzj := GameState.make_item("dzj")
	dzj.plus = 7
	var ring_mats := [dzj, GameState.make_item("t"), GameState.make_item("c")]
	var ring := Forge.produce(Forge.recipe_for(ring_mats), ring_mats)
	var hp: float = ring.stats.get("hp", 0.0)
	var atk: float = ring.stats.get("atk", 0.0)
	_check("dzjj sums its materials", ring.id == "dzjj" and ring.plus == 0 and hp >= 300 + 350 + 100 and hp <= 300 + 350 + 300 and atk >= 30 + 70 + 10 and atk <= 30 + 70 + 30)
	# 白霜 three of a kind: the product rolls its own ranges, nothing of its materials (bsxj -> bszj)
	var frost_ok := true
	for i in 20:
		var fm := [GameState.make_item("bsxj"), GameState.make_item("bsxj"), GameState.make_item("bsxj")]
		for m in fm:
			m.stats["hp"] = 9999.0
			m.stats["def"] = 999.0
		var fr := Forge.recipe_for(fm)
		var fo := Forge.produce(fr, fm)
		var d := GameState.item_data(fo)
		for k in d.stats:
			var rg: Vector2 = d.stats[k]
			var v := float(fo.stats.get(k, 0.0))
			if fo.id != "bszj" or v < rg.x - 0.001 or v > rg.y + 0.001:
				frost_ok = false
	_check("白霜 fusion rolls the product's own stats", frost_ok)
	# equipment stat rolls cover the whole range, ends as often as the middle (the original's round(rand * k) halved the ends)
	var counts := {}
	for i in 6000:
		var v := int(EquipmentCatalog.find("ptxzg").roll().stats.atk)
		counts[v] = counts.get(v, 0) + 1
	var lo: int = counts.keys().min()
	var hi: int = counts.keys().max()
	_check("stat roll ends as likely as the middle", counts[lo] > 0.7 * counts[(lo + hi) / 2] and counts[hi] > 0.7 * counts[(lo + hi) / 2])
	# shop
	GameState.merit = 1000
	_check("buy stones", Forge.buy("wpqhs1", 3) == "购买成功" and GameState.count_of("wpqhs1") == 3 and GameState.merit == 910)
	GameState.merit = 100
	_check("merit short", Forge.buy("wkzyf", 1) == "功勋不足")
	_check("merit reward once a day", Forge.reward_merit(60) == 50 and Forge.reward_merit(60) == 0 and Forge.reward_merit(39) == 0)
	# screens
	for id in ["dslj", "dsqz", "dsyj", "wpxyf", "wpbdf", "ptxzg"]:
		GameState.add_to_bag(GameState.make_item(id))
	var f := ForgeScreen.new()
	add_child(f)
	await get_tree().create_timer(0.3).timeout
	f._put(GameState.bag.find_custom(func(i): return i.id == "ptxzg"))
	f._tab = "btn_dj"
	f._refresh()
	f._put(GameState.bag.find_custom(func(i): return i.id == "wpqhs1"))
	f._put(GameState.bag.find_custom(func(i): return i.id == "wpxyf"))
	await get_tree().create_timer(0.2).timeout
	_check("forge slots", f._slots.zbmc != null and f._slots.qhmc1 != null and GameState.count_of("wpqhs1") == 2)
	_shot("forge_strength")
	f._show_page(true)
	_check("slots returned", GameState.count_of("wpqhs1") == 3 and GameState.has_item("ptxzg"))
	f._tab = "btn_zb"
	f._refresh()
	for id in ["dslj", "dsqz", "dsyj"]:
		f._put(GameState.bag.find_custom(func(i): return i.id == id))
	await get_tree().create_timer(0.2).timeout
	_shot("forge_fusion_ready")
	var souls := GameState.souls
	f._do_fusion()
	await get_tree().create_timer(0.2).timeout
	_check("fusion done", GameState.has_item("dshl") and GameState.souls == souls - 1000 and not GameState.has_item("dslj"))
	_shot("forge_fusion_done")
	f.close()
	var shop := ShopScreen.new()
	add_child(shop)
	await get_tree().create_timer(0.3).timeout
	_shot("shop")
	shop._show_tab("btn_buygx")
	await get_tree().create_timer(0.2).timeout
	_shot("shop_look")
	print("FORGE CHECK %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(1 if _fails else 0)

func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])

func _shot(n: String) -> void:
	if _out != "":
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, n])
