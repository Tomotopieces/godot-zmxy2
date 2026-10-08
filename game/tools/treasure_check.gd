extends Node
## Uses every magic treasure in 1-1 against a few monsters and checks that each one does its job.
##   godot --headless --path game res://tools/treasure_check.tscn
##   godot --path game res://tools/treasure_check.tscn -- --out=<dir>     (a screenshot of each skill)

const IDS := ["dshl", "tsgj", "bsj", "lsys", "xhmt", "wds"]
const MONSTER := 31

var _out := ""
var _fails := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	GameState.new_game()
	GameState.souls = 1000000
	var main: PlayScreen = PlayScreen.create(Vector2i(1, 1))
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	var lv: Level = main.level
	var h: Hero = lv.hero
	for id in IDS:
		var it := GameState.make_item(id)
		Forge._init_treasure(it, GameState.hero_data.treasures.get(id, {}).merged(EquipmentCatalog.get_catalog().treasures.defs[id]))
		GameState.add_to_bag(it)
		GameState.wear(GameState.bag.find(it))
		await get_tree().physics_frame
		_check(id + " companion", is_instance_valid(h.treasure) and h.treasure.id == id)
		var mons: Array[Monster] = []
		for k in 3:
			var m := Monster.create(lv.monster_data(MONSTER))
			m.position = h.global_position + Vector2(160 + k * 70, -40)
			lv.add_monster(m)
			mons.append(m)
		await get_tree().create_timer(0.3).timeout
		var hp0 := mons.map(func(m): return m.hp)
		h.mp = h.max_mp
		h.hp = h.max_hp / 2
		var mp0 := h.mp
		h.treasure.use()
		_check(id + " used", h.treasure.using and h.mp == mp0 - Forge.skill_cost(it))
		var shot := false
		var t := 0.0
		while t < 20.0 and (h.treasure.using or t < 4.0):
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if not shot and t > 0.8:
				shot = true
				_shot("treasure_" + id)
			h.hp = maxi(h.hp, 1)
		var hurt := false
		for k in mons.size():
			hurt = hurt or not is_instance_valid(mons[k]) or mons[k].hp < hp0[k]
		_check(id + " hurt a monster", hurt)
		_check(id + " finished", not h.treasure.using)
		for m in mons:
			if is_instance_valid(m):
				m.queue_free()
		await get_tree().create_timer(0.3).timeout
	# level up
	var w: Dictionary = GameState.worn[&"treasure"]
	var atk0 := float(w.stats.atk)
	Forge.upgrade(w)
	_check("wds level 2", w.lv == 2 and w.stats.atk >= atk0 + 10)
	var s := SutraPanel.open_on(main.hud)
	await get_tree().create_timer(0.3).timeout
	_shot("sutra_panel")
	s._on_button("btn_sj")
	_check("upgrade from panel", w.lv == 3)
	s.queue_free()
	print("TREASURE CHECK %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))
	get_tree().quit(1 if _fails else 0)

func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])

func _shot(n: String) -> void:
	if _out != "":
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, n])
