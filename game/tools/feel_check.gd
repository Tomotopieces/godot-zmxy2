extends Node
## Game-feel checks: input buffer, turning between moves, hit-stop, camera shake (headless).
## godot --headless --path game res://tools/feel_check.tscn
var _fails := 0
var _ps: PlayScreen

func _check(what: String, ok: bool) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _ready() -> void:
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(2))
	GameState.new_game("wukong")
	for s in GameState.hero_data.learn_active:
		GameState.skills[StringName(s)] = true
	_ps = PlayScreen.create(Vector2i(1, 1))
	add_child(_ps)
	await _wait(1.0)
	var lv := _ps.level
	var h := lv.hero
	h.invincible = 999.0
	GameState.level = 30
	h.refill()
	lv.stops.clear()

	# 1. an attack pressed during the attack lock comes out when the lock ends (it used to be lost)
	await _press("attack")
	var first := h.attack_action
	await _until(func(): return h.cooldown < 0.08, 2.0)
	await _press("attack")   # early: still locked, inside the buffer window
	await _wait(0.12)
	_check("buffered attack comes out after the lock (%s -> %s)" % [first, h.attack_action], h.attack_action != first and h.state == Hero.State.ATTACK)
	await _until_idle(h)

	# 2. a press older than the window is dropped
	h.cooldown = 1.0
	h.state = Hero.State.MOVE
	await _press("attack")
	await _wait(0.5)
	h.cooldown = 0.0
	await _wait(0.1)
	_check("a press older than the buffer is dropped", h.state == Hero.State.MOVE)

	# 3. jump pressed just before landing jumps on landing
	await _press("jump")
	await _wait(0.2)
	await _press("jump")   # second jump
	await _until(func(): return h.velocity.y > 0.0 and not h.is_on_floor(), 3.0)
	await _until(func(): return h.global_position.y > lv.hero.global_position.y - 1.0 and _near_floor(h), 3.0)
	await _press("jump")
	var jumped := false
	for i in 30:
		await get_tree().physics_frame
		if h.velocity.y < 0.0:
			jumped = true
			break
	_check("jump pressed before landing jumps on landing", jumped)
	await _until(func(): return h.is_on_floor(), 3.0)
	await _wait(0.2)

	# 4. turning: no turn while a move plays; the next move goes the way the held direction points
	#    (back pressed during combo hit 4 -> hit 5 goes the other way)
	h.facing = 1
	for i in 4:
		await _until(func(): return h.cooldown <= 0.0, 2.0)
		await _press("attack")
		await _wait(0.02)
	var hit4 := h.attack_action
	Input.action_press("move_left")
	await _wait(0.05)
	var f4 := h.facing
	await _until(func(): return h.attack_action != hit4 or h.state == Hero.State.MOVE, 2.0)
	await _until(func(): return h.cooldown <= 0.0, 2.0)
	await _press("attack")
	await _wait(0.02)
	var f5 := h.facing
	var hit5 := h.attack_action
	Input.action_release("move_left")
	_check("no turn while %s plays (facing %d)" % [hit4, f4], f4 == 1)
	_check("next hit %s goes the held way (facing %d)" % [hit5, f5], f5 == -1 and hit5 != hit4)
	await _until_idle(h)
	h.facing = 1
	await _press("skill_i")   # 烈焰风暴
	await _wait(0.1)
	Input.action_press("move_left")
	await _wait(0.1)
	var f6 := h.facing
	await _until(func(): return h.state == Hero.State.MOVE or h.puppet.progress() >= h.data.cancel_progress, 4.0)
	await _until(func(): return h.cooldown <= 0.0, 2.0)
	await _wait(0.05)
	await _press("skill_u")
	await _until(func(): return h.attack_action == &"hit7", 1.0)
	var f7 := h.facing
	Input.action_release("move_left")
	_check("no turn while a skill plays (facing %d)" % f6, f6 == 1)
	_check("next move turned to the held direction (facing %d at %s)" % [f7, h.attack_action], f7 == -1 and h.attack_action == &"hit7")
	await _until_idle(h)
	Input.action_release("move_left")

	# 5. hit-stop: a monster in front, hit5 freezes attacker and target; camera shake decays
	h.facing = 1
	var md: MonsterData = load("res://data/monsters/monster_30.tres").duplicate()
	md.hp = 99999
	var m := Monster.create(md)
	m.global_position = h.global_position + Vector2(60, 0)
	lv.add_monster(m)
	await _wait(0.3)
	GameState.debug_god = true   # (the monster fights back: a hit on the hero would break the combo under test)
	var stopped := false
	var both := false
	var shook := false
	var stop_max := 0.0
	for i in 5:
		m.global_position = h.global_position + Vector2(60, 0)
		m.velocity = Vector2.ZERO
		h.combo_step = i   # (the chain itself depends on press timing; each step is set so the 5th hit is hit5)
		h._last_attack_at = h._clock
		h.cooldown = 0.0
		await _press("attack")
		for f in 30:
			await get_tree().physics_frame
			if lv.stop_t > 0.0:
				stopped = true
				stop_max = maxf(stop_max, lv.stop_t)
				both = both or (lv.world.process_mode == Node.PROCESS_MODE_DISABLED and not h.can_process() and not m.can_process())
			if lv._trauma > 0.0:
				shook = true
		print("  combo hit ", h.attack_action, " trauma ", lv._trauma, " monster hp ", m.hp, " dx ", m.global_position.x - h.global_position.x)
		await _wait(0.25)
	GameState.debug_god = false
	_check("hit-stop freezes the whole fight (max %.3f s)" % stop_max, stopped and both and stop_max <= 0.2)
	_check("the 5th combo hit shakes the camera", shook)
	await _wait(1.0)
	lv.add_trauma(0.6)
	await _wait(0.05)
	_check("trauma moves the camera", lv.camera.offset.length() > 0.5)
	await _wait(1.0)
	_check("camera shake has faded", lv.camera.offset == Vector2.ZERO)
	_check("no time_scale change", Engine.time_scale == 1.0)
	# a menu still works during a hit-stop: the stop holds while the tree is paused and resumes after
	lv.hit_stop(0.1)
	get_tree().paused = true
	await get_tree().create_timer(0.3, true, false, true).timeout
	var held := lv.stop_t > 0.0
	get_tree().paused = false
	await _wait(0.2)
	_check("a hit-stop waits while a menu is open, then ends", held and lv.stop_t == 0.0 and h.can_process())
	print("FEEL CHECK ", "FAILED (%d)" % _fails if _fails else "OK")
	get_tree().quit(1 if _fails else 0)

func _near_floor(h: Hero) -> bool:
	var q := PhysicsRayQueryParameters2D.create(h.global_position, h.global_position + Vector2(0, 30), Actor.LAYER_WORLD | Actor.LAYER_ONEWAY)
	return not h.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _press(k: String) -> void:
	Input.action_press(k)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(k)

func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout

func _until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while not cond.call() and t < limit:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second

func _until_idle(h: Hero) -> void:
	await _until(func(): return h.state == Hero.State.MOVE and h.cooldown <= 0.0, 5.0)
	await _wait(0.1)
