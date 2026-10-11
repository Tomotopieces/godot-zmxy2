extends Node
## Every boss leaves its loot when it finally dies, however many forms it has: souls (red orbs) and the 小月饼 (中秋). Each boss is
## fought alone in the debug arena and killed again and again until it is gone.
##   godot --headless --path game --fixed-fps 60 res://tools/loot_check.tscn [-- <id,id,...>]
## Prints "FAIL <id> ..." for a boss that died without loot or never went away.

const MAX_SECONDS := 120.0

var _orbs := 0
var _cakes := 0
var _frame := 0
var _last_died := -1        ## frame of the last boss death
var _last_orb := -1         ## frame of the last soul orb / 小月饼
var _last_cake := -1

func _ready() -> void:
	var ids: Array[int] = []
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		for s in args[0].split(","):
			ids.append(int(s))
	else:
		for i in range(30, 82):
			var md := load("res://data/monsters/monster_%d.tres" % i) as MonsterData
			if md != null and md.is_boss and i != 79:   # (79 stands for 劈天斧 / 风神盾: the arena picks one of them)
				ids.append(i)
	var failed := 0
	for id in ids:
		var problem := await _fight(id)
		if problem != "":
			failed += 1
			print("FAIL %d %s" % [id, problem])
	print("loot_check: %d bosses, %d failed" % [ids.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)

func _fight(id: int) -> String:
	GameState.new_game("wukong")
	Rng.seed_with(id)
	var md := load("res://data/monsters/monster_%d.tres" % id) as MonsterData
	Level.arena_boss = md
	var ps := PlayScreen.create(Level.ARENA)
	add_child(ps)
	_orbs = 0
	_cakes = 0
	_frame = 0
	_last_died = -1
	_last_orb = -1
	_last_cake = -1
	var lv: Level
	var tracked := {}   ## instance id of every monster that took part
	var frames := 0
	while frames < int(MAX_SECONDS * 60.0):
		await get_tree().physics_frame
		frames += 1
		_frame = frames
		lv = Level.current
		if lv == null or not is_instance_valid(lv.hero):
			continue
		lv.hero.hp = lv.hero.max_hp
		for n in lv.world.get_children():
			if n is Orb and not n.has_meta(&"counted"):
				n.set_meta(&"counted", true)
				if n.kind == Orb.Kind.RED:
					_orbs += 1
					_last_orb = frames
			elif n is GroundItem and not n.has_meta(&"counted"):
				n.set_meta(&"counted", true)
				if n.item.id == EquipmentCatalog.get_catalog().moon.cake:
					_cakes += 1
					_last_cake = frames
		var monsters := lv.monsters()
		for m: Monster in monsters:
			if not tracked.has(m.get_instance_id()):
				tracked[m.get_instance_id()] = true
				if m.data.is_boss:
					m.died.connect(func(_m): _last_died = _frame)
		if not tracked.is_empty() and tracked.keys().all(func(i): return not is_instance_valid(instance_from_id(i)) or (instance_from_id(i) as Node).is_queued_for_deletion()):
			break   # every one of them has been removed from the level
		if frames % 30 == 0:
			for m: Monster in monsters:
				if m.data.is_boss and m.can_be_hit():
					m.damage_directly(m.max_hp)
	ps.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if tracked.is_empty():
		return "never appeared"
	if frames >= int(MAX_SECONDS * 60.0):
		return "not gone after %d s (a final death that never finishes)" % int(MAX_SECONDS)
	if _last_died < 0:
		return "no boss ever died"
	if _last_cake < _last_died:
		return "no 小月饼 after its last death"
	if md.souls > 0 and _last_orb < _last_died:
		return "no soul orbs after its last death (souls=%d)" % md.souls
	return ""
