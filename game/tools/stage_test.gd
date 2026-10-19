extends Node
## Headless checks of stage scripts: godot --headless --path game res://tools/stage_test.tscn -- <case>
## cases: door12, door12_tangseng, hub, fires, boat, pearls
var _case := ""
var _ps: PlayScreen
var _transfers: Array = []
var _failed := false

func _ready() -> void:
	_case = OS.get_cmdline_user_args()[0]
	GameState.new_game("tangseng" if _case == "door12_tangseng" else "wukong")
	for s in GameState.hero_data.learn_active:
		GameState.skills[StringName(s)] = true
	var stage := {"door12": Vector2i(1, 2), "door12_tangseng": Vector2i(1, 2), "hub": Vector2i(10, 1), "fires": Vector2i(2, 2), "boat": Vector2i(3, 1), "pearls": Vector2i(3, 3)}
	_ps = PlayScreen.create(stage[_case])
	add_child(_ps)
	_ps.level.transfer.connect(func(to): _transfers.append(to))
	_ps.level.failed.connect(func(): _failed = true)
	call(_case)

func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout

func _attack_at(pos: Vector2) -> void:
	var h := _ps.level.hero
	h.invincible = 999.0
	h.global_position = pos
	h.velocity = Vector2.ZERO
	h.facing = 1
	Input.action_press("attack")
	await _wait(0.1)
	Input.action_release("attack")
	await _wait(0.6)

func door12() -> void:
	await _wait(1.0)
	var door: BaiguDoor = _ps.level.world.get_node("Objects/BaiguDoor")
	door.global_position = Vector2(480.0, 336.0)   # the first screen: the headless camera does not follow a hero teleported far away
	var box: Rect2 = door.weak_rect()
	_ps.level.stops.clear()
	for i in 8:   # (唐僧's attack has a cooldown: some presses are not attacks)
		if door.is_open():
			break
		# stand left of the weak spot at its height (no gravity during the test)
		_ps.level.hero.gravity = 0.0
		await _attack_at(box.get_center() + Vector2(-70, -10))
	print("door open=", door.is_open(), " hits_left=", door.hits_left())
	_ps.level.hero.global_position = door.enter_world_rect().get_center()
	Engine.time_scale = 4.0
	await _wait(6.0)
	print("RESULT door12 transfers=", _transfers)
	get_tree().quit()

## 唐僧 hits only with bullets: they must break the weak spot too.
func door12_tangseng() -> void:
	await door12()

func hub() -> void:
	await _wait(1.0)
	var sc = _ps.level.script_node
	var h := _ps.level.hero
	h.gravity = 0.0
	for round in 2:
		# advance the selector to the wanted pointer, then hit both stones "together"
		var want := 1 if round == 0 else 4
		while (sc._selector.brain as HubPropBrain).pointer != want:
			sc._selector.invuln = 0.0
			await _attack_at(sc._selector.center() + Vector2(-60, 0))
		for s in sc._stones:
			(s.brain as HubPropBrain)._hit_t = 0.5
		await _wait(1.5)
		print("pointer=", want, " door2_ready=", sc._doors[1].ready_to_enter, " statue_ready=", sc._statue.ready_to_enter)
	h.global_position = sc._doors[1].enter_world_rect().get_center()
	Input.action_press("move_up")
	await _wait(0.1)
	Input.action_release("move_up")
	await _wait(0.2)
	print("RESULT hub transfers=", _transfers)
	get_tree().quit()

func fires() -> void:
	await _wait(0.5)
	var lv := _ps.level
	var m := Monster.create(lv.monster_data(39))
	m.position = Vector2(4491, 381)
	lv.add_monster(m)
	lv.hero.global_position = Vector2(3700, 400)
	lv.hero.invincible = 9999.0
	lv.view_x = 3400
	Engine.time_scale = 10.0
	var t0 := Time.get_ticks_msec()
	while not _failed and Time.get_ticks_msec() - t0 < 30000:
		await _wait(1.0)
		lv.hero.global_position = Vector2(3500, 400)
	print("RESULT fires failed=", _failed, " after game seconds ~", (Time.get_ticks_msec() - t0) / 100.0, " started=", (m.brain as Object).get("_started") if is_instance_valid(m) else "?")
	get_tree().quit()

func boat() -> void:
	await _wait(0.5)
	var lv := _ps.level
	var sc = lv.script_node
	lv.hero.invincible = 99999.0
	Engine.time_scale = 10.0
	var t0 := Time.get_ticks_msec()
	var fell := false
	while not lv.door_open() and Time.get_ticks_msec() - t0 < 25000:
		await _wait(0.5)
		if not is_instance_valid(lv.hero) or lv.hero.global_position.y > 700:
			fell = true
			break
	print("RESULT boat door=", lv.door_open(), " boat_x=", sc._boat.position.x, " hero=", lv.hero.global_position, " fell=", fell, " on_floor=", lv.hero.is_on_floor(), " monsters=", lv.monsters().size())
	get_tree().quit()

func pearls() -> void:
	await _wait(0.5)
	var sc = _ps.level.script_node
	var r: Rig = sc._pearls[0][0]
	_ps.level.stops.clear()
	_ps.level.view_x = r.position.x - 400
	_ps.level.hero.gravity = 0.0
	for i in 6:
		await _attack_at(r.position + Vector2(-70, -10))
	print("RESULT pearls hp=", sc._pearls[0][1], " valid=", is_instance_valid(r))
	get_tree().quit()
