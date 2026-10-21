class_name PlayScreen
extends Node
## One stage being played: Level + HUD, backpack, pause menu, win / fail screens.
## Keys: C bag, Esc pause menu, 5 restart, 1 refill HP/MP/rage, 2 hit boxes, 3 test gear, 4 kill all monsters, 6 invincible (no damage, no knockback).

signal to_map
signal to_menu
signal play(stage: Vector2i)   ## retry / next stage

## 3 debug: one of each Wukong weapon / armour tier plus accessories.
const TEST_GEAR := ["ptxzg", "gtq", "tsyj", "gwj", "ryjgb", "ptxzf", "dsyj", "bsxj", "xhmj", "dszk", "dslj", "tsgl", "lzp",
	"csgs", "wkmrz", "wkwdg", "wkbsz", "wkzyf", "xtzy", "ttzy", "sbbl", "jxbuff", "hhbuff", "wpqhs1", "wpqhs1", "yll", "bsz",
	"dslj", "dsqz", "dsyj"]
const TEST_SOULS := 50000
const TEST_MERIT := 5000
const HUD_SCENE := preload("res://scenes/screens/hud.tscn")
const RESULT_DELAY := 1.0   ## wait before the fail / ending screens (original: 1 s)
const CLEAR_FADE := 0.5     ## stage clear: fade to white (the original fades to white for 1 s)

## The whole screen (scene and HUD) fades to white (the original fades to white: Role1 enters the exit, gameInfo / gameSence alpha -> 0).
func _fade_out() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var white := ColorRect.new()
	white.color = Color(1, 1, 1, 0)
	white.size = Layers.VIEW
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(white)
	var tw := create_tween()
	tw.tween_property(white, "color:a", 1.0, CLEAR_FADE)
	await tw.finished

var stage := Vector2i(1, 1)
var level: Level
var hud: Hud
var _over := false
var _menu: TabMenu
var _start_time := 0.0

static func create(s: Vector2i) -> PlayScreen:
	var p := PlayScreen.new()
	p.stage = s
	return p

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if stage != Level.ARENA:   # the debug boss arena is not a place a save should remember
		GameState.stage = stage
	hud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.open_bag.connect(open_menu.bind(&"bag"))
	hud.open_menu.connect(open_pause)
	hud.open_skills.connect(open_menu.bind(&"skill"))
	hud.open_treasure.connect(open_menu.bind(&"treasure"))
	level = Level.new()
	level.stage = stage
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	level.hero_died.connect(_on_hero_died)
	level.stage_cleared.connect(_on_cleared)
	level.gogo.connect(hud.play_gogo)
	level.message.connect(hud.toast)
	level.rage_started.connect(hud.play_rage_transform)
	level.combo_changed.connect(hud.show_combo)
	level.boss_spawned.connect(hud.add_boss_bar)
	level.ending.connect(_on_ending)
	level.failed.connect(_on_hero_died)
	level.transfer.connect(func(to): play.emit(to))   # hidden stage entrances skip the result screen
	add_child(level)
	move_child(level, 0)
	_start_time = Time.get_ticks_msec() / 1000.0

func _exit_tree() -> void:
	get_tree().paused = false

## The fight is over: nothing in the stage moves any more (a boss that revives, a timer, a monster that still attacks),
## whatever the player does on the result screen.
func _freeze_level() -> void:
	if is_instance_valid(level):
		level.process_mode = Node.PROCESS_MODE_DISABLED

func _on_hero_died() -> void:
	_over = true
	Snd.stop_music()
	await get_tree().create_timer(RESULT_DELAY).timeout
	if not is_inside_tree():
		return
	_freeze_level()
	Snd.music("over", false)
	var r := ResultScreen.fail(stage)
	r.retry.connect(func(): play.emit(stage))
	r.back.connect(func(): to_map.emit())
	add_child(r)

func _on_cleared() -> void:
	_over = true
	var is_main := stage.x <= 4
	if is_main:
		GameState.on_stage_cleared(stage)
	var h := level.hero
	var stats := {
		"time": Time.get_ticks_msec() / 1000.0 - _start_time,
		"state": roundi(50.0 * (float(h.hp) / h.max_hp + float(h.mp) / h.max_mp)),
		"combo": level.best_combo,
	}
	await _fade_out()
	if not is_inside_tree():
		return
	_freeze_level()   # the fight stops when the result appears, not during the fade
	var r := ResultScreen.win(stage, stats)
	r.next.connect(func(): play.emit(GameState.next_stage(stage)))
	r.back.connect(func(): to_map.emit())
	add_child(r)
	Snd.music("begin")
	Snd.sfx("Game_Victory")
	if GameState.autosave():
		Toast.show_on(r, "存档成功")
	else:
		var panel := SavePanel.create(SavePanel.Mode.SAVE)
		add_child(panel)

## Final boss (4-1): progress, autosave, the ending comic, then the map.
func _on_ending() -> void:
	_over = true
	GameState.on_stage_cleared(stage)
	GameState.autosave()
	await get_tree().create_timer(RESULT_DELAY).timeout
	if not is_inside_tree():
		return
	_freeze_level()
	var c := Cartoon.create("通关")
	c.finished.connect(func(): to_map.emit())
	add_child(c)

## The in-game menu (背包 / 技能 / 法宝 / 设置) on one of its tabs; 法宝 without a worn treasure only says so.
func open_menu(tab: StringName) -> void:
	if _over or _menu or get_tree().paused:
		return
	if tab == &"treasure" and GameState.worn[&"treasure"] == null:
		Toast.show_on(hud, "请先装备法宝")
		return
	_menu = TabMenu.create(tab)
	_menu.tree_exited.connect(func(): _menu = null)
	_menu.to_map.connect(func(): to_map.emit())
	_menu.to_menu.connect(func(): to_menu.emit())
	add_child(_menu)

func open_pause() -> void:
	open_menu(&"settings")

## 3 debug gear: the shared pieces plus every weapon / armour / fashion of this hero.
func _test_gear() -> Array:
	var out: Array = []
	for id in TEST_GEAR:
		var d := EquipmentCatalog.find(id)
		if d and (d.user == "" or d.user == GameState.hero_data.character) and d.type != &"fashion":
			out.append(id)
	for id in EquipmentCatalog.get_catalog().items:
		var d: EquipmentData = EquipmentCatalog.get_catalog().items[id]
		if d.user == GameState.hero_data.character and d.type in [&"weapon", &"cloth", &"fashion"] and not id in out:
			out.append(String(id))
	return out

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("open_bag"):
		open_menu(&"bag")
	elif e.is_action_pressed("pause"):
		open_pause()
	elif e.is_action_pressed("open_skills"):
		open_menu(&"skill")
	elif e.is_action_pressed("open_treasure"):
		open_menu(&"treasure")
	elif OS.is_debug_build() and e.is_action_pressed("debug_give_items"):
		for id in _test_gear():
			GameState.add_to_bag(EquipmentCatalog.find(id).roll())
		GameState.add_souls(TEST_SOULS)
		GameState.merit += TEST_MERIT
		hud.toast("测试装备、灵魂和功勋已放入背包")
	elif OS.is_debug_build() and e.is_action_pressed("debug_restart"):
		play.emit(stage)
