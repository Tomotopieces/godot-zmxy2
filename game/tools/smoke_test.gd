extends Node
## Bot run of the first stage: walks right, attacks and uses skills, logs progress, saves screenshots.
##   godot --path game res://tools/smoke_test.tscn -- --out=<dir> [--time=60] [--stage=2,1]

var _main: Node
var _t := 0.0
var _shot_t := 0.0
var _out := ""
var _limit := 60.0
var _kills := 0
var _shots := 0
var _stage := Vector2i(1, 1)
var _spawn_id := 0          ## --spawn=<monster id>: put that monster next to the hero and fight it
var _spawned: Monster
var _last_act := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--time="):
			_limit = a.substr(7).to_float()
		elif a.begins_with("--spawn="):
			_spawn_id = int(a.substr(8))
		elif a.begins_with("--stage="):
			var p := a.substr(8).split(",")
			_stage = Vector2i(int(p[0]), int(p[1]))
	GameState.new_game()
	for s in GameState.hero_data.learn_active:
		GameState.skills[StringName(s)] = true
	_main = PlayScreen.create(_stage)
	add_child(_main)

func _press(a: String, on: bool) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)

func _physics_process(delta: float) -> void:
	_t += delta
	var lv := Level.current
	if lv == null or not is_instance_valid(lv.hero):
		return
	var h := lv.hero
	_watch_flicker(h)
	if _spawn_id > 0:
		_watch_spawn(lv, h)
	_watch_camera(lv)
	if not h.died.is_connected(_on_died):
		h.died.connect(_on_died)
	h.invincible = maxf(h.invincible, 0.1) if _t < _limit else h.invincible
	var ms := lv.monsters()
	var near := false
	for m in ms:
		if m.can_be_hit() and absf(m.global_position.x - h.global_position.x) < 160:
			near = true
			h.facing = 1 if m.global_position.x > h.global_position.x else -1
	_press("move_right", not near)
	var phase := int(_t * 6.0) % 12
	_press("attack", near and phase % 2 == 0)
	_press("skill_u", near and phase == 5)
	_press("skill_i", near and phase == 9)
	_press("skill_o", near and int(_t) % 7 == 0 and phase == 1)
	_press("jump", not near and int(_t * 2.0) % 6 == 0)
	if int(_t * 10) % 20 == 0:
		print("fps=%d " % Engine.get_frames_per_second(), "t=%.1f x=%.0f y=%.0f view=%.0f stop=%d locked=%s mon=%d hp=%d mp=%d rage=%d st=%s act=%s lv=%d exp=%d door=%s" % [
			_t, h.global_position.x, h.global_position.y, lv.view_x, lv.stop_index, lv.locked, ms.size(),
			h.hp, h.mp, h.rage, Hero.State.keys()[h.state], h.rig.action, GameState.level, GameState.exp, lv.door_open()])
	_shot_t += delta
	if _out != "" and _shot_t > 6.0:
		_shot_t = 0.0
		_shots += 1
		get_viewport().get_texture().get_image().save_png("%s/smoke_%02d.png" % [_out, _shots])
	if lv.door_open():
		h.mp = h.max_mp
		var to_door := lv.door_rect.get_center().x - h.global_position.x
		_press("move_right", to_door > 10)
		_press("move_left", to_door < -10)
		_press("move_up", absf(to_door) < 40)
	if _t > _limit:
		print("END monsters_left=%d stop=%d/%d door=%s souls=%d exp=%d lv=%d" % [ms.size(), lv.stop_index, lv.stops.size(), lv.door_open(), GameState.souls, GameState.exp, GameState.level]); print("BAG ", GameState.bag.map(func(i): return i.id))
		get_tree().quit()

func _watch_spawn(lv: Level, h: Hero) -> void:
	if _spawned == null and _t > 1.5:
		_spawned = Monster.create(lv.monster_data(_spawn_id))
		_spawned.position = h.global_position + Vector2(300, -60)
		lv.add_monster(_spawned)
		lv.locked = true
		print("SPAWN ", _spawn_id, " hp=", _spawned.max_hp)
	if is_instance_valid(_spawned):
		var a := "%s/%s" % [Monster.State.keys()[_spawned.state], _spawned.rig.action]
		if a != _last_act:
			_last_act = a
			print("t=%.1f M%d %s hp=%d inv=%.1f pos=(%.0f,%.0f) objs=%d" % [_t, _spawn_id, a, _spawned.hp, _spawned.invuln, _spawned.global_position.x, _spawned.global_position.y, lv.world.get_child_count()])
	elif _spawned != null and _last_act != "gone":
		_last_act = "gone"
		print("t=%.1f M%d gone, door=%s monsters=%d" % [_t, _spawn_id, lv.door_open(), lv.monsters().size()])

## Report actions that last only 1-2 physics frames and frames where the hero draws nothing.
var _hist: Array = []
var _flicker := {}

func _watch_flicker(h: Hero) -> void:
	_hist.append(h.rig.action)
	if _hist.size() > 4:
		_hist.pop_front()
	if _hist.size() == 4 and _hist[0] == _hist[3] and _hist[1] != _hist[0]:
		var k := "%s>%s>%s" % [_hist[0], _hist[1], _hist[3]]
		_flicker[k] = _flicker.get(k, 0) + 1
	var parts := h.rig.current_pose()
	var shown := 0
	for c in parts.get_children():
		if c.visible:
			shown += 1
	if shown == 0:
		var k := "empty:" + String(h.rig.action)
		_flicker[k] = _flicker.get(k, 0) + 1

## Camera smoothness: biggest single-tick scroll, and "stutter" = scroll step that differs from
## the previous one by more than 4 px while both are non-zero or one is zero mid-scroll.
var _last_view := 0.0
var _last_step := 0.0
var _max_step := 0.0
var _stutter := 0

func _watch_camera(lv: Level) -> void:
	var step := lv.view_x - _last_view
	_last_view = lv.view_x
	if absf(step) > 200.0:   # level (re)start
		return
	_max_step = maxf(_max_step, absf(step))
	if absf(step - _last_step) > 4.0 and (step != 0.0 and _last_step != 0.0 or absf(step - _last_step) > 6.0):
		_stutter += 1
	_last_step = step

func _exit_tree() -> void:
	print("FLICKER ", _flicker)
	print("CAMERA max_step=%.1f stutter=%d" % [_max_step, _stutter])

func _on_died(_a) -> void:
	print("HERO DIED at t=%.1f" % _t)
