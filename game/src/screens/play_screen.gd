class_name PlayScreen
extends Node
## One stage being played: Level + HUD, backpack, pause menu, win / fail screens.
## Keys: C bag, Esc pause menu, F5 restart, F1 refill HP/MP/rage, F2 hit boxes, F3 test gear, F4 kill all monsters.

signal to_map
signal to_menu
signal play(stage: Vector2i)   ## retry / next stage

## F3 debug: one of each Wukong weapon / armour tier plus accessories.
const TEST_GEAR := ["ptxzg", "gtq", "tsyj", "gwj", "ryjgb", "ptxzf", "dsyj", "bsxj", "xhmj", "dszk", "dslj", "tsgl", "lzp",
	"csgs", "wkmrz", "wkwdg", "wkbsz", "wkzyf", "xtzy", "ttzy", "sbbl", "jxbuff", "hhbuff", "wpqhs1", "wpqhs1", "yll", "bsz",
	"dslj", "dsqz", "dsyj"]
const TEST_SOULS := 50000
const TEST_MERIT := 5000
const RESULT_DELAY := 1.0   ## fade before the result screen (original: 1 s fade of gameInfo / gameSence)

## The whole screen (scene and HUD) fades to black (Role1 enters the exit: gameInfo / gameSence alpha -> 0).
func _fade_out() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.size = Layers.VIEW
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 1.0, RESULT_DELAY)
	await tw.finished

var stage := Vector2i(1, 1)
var level: Level
var hud: Hud
var _over := false
var _bag: Backpack
var _menu: Node
var _start_time := 0.0

static func create(s: Vector2i) -> PlayScreen:
	var p := PlayScreen.new()
	p.stage = s
	return p

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.stage = stage
	hud = Hud.new()
	add_child(hud)
	hud.open_bag.connect(_open_bag)
	hud.open_menu.connect(_open_pause)
	hud.open_skills.connect(_open_skills)
	hud.open_treasure.connect(_open_treasure)
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
	_freeze_level()
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
	_freeze_level()
	GameState.on_stage_cleared(stage)
	GameState.autosave()
	await get_tree().create_timer(RESULT_DELAY).timeout
	if not is_inside_tree():
		return
	var c := Cartoon.create("通关")
	c.finished.connect(func(): to_map.emit())
	add_child(c)

func _open_bag() -> void:
	if _bag or _over or get_tree().paused:
		return
	_bag = Backpack.new()
	_bag.closed.connect(func(): _bag = null)
	add_child(_bag)

func _open_skills() -> void:
	if _over or _bag or _menu or get_tree().paused:
		return
	var m := SkillShop.new()
	_menu = m
	m.tree_exited.connect(func(): _menu = null)
	add_child(m)

## 法宝升级 (HUD 法宝 button).
func _open_treasure() -> void:
	if _over or _bag or _menu or get_tree().paused:
		return
	var s := SutraPanel.open_on(hud)
	if s:
		_menu = s
		s.tree_exited.connect(func(): _menu = null)

func _open_pause() -> void:
	if _over or _bag or _menu or get_tree().paused:
		return
	var m := PauseMenu.new()
	_menu = m
	m.closed.connect(func(): _menu = null)
	m.to_map.connect(func(): to_map.emit())
	m.to_menu.connect(func(): to_menu.emit())
	add_child(m)

## F3 debug gear: the shared pieces plus every weapon / armour / fashion of this hero.
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
		_open_bag()
	elif e.is_action_pressed("pause"):
		_open_pause()
	elif e.is_action_pressed("open_skills"):
		_open_skills()
	elif OS.is_debug_build() and e.is_action_pressed("debug_give_items"):
		for id in _test_gear():
			GameState.add_to_bag(EquipmentCatalog.find(id).roll())
		GameState.add_souls(TEST_SOULS)
		GameState.merit += TEST_MERIT
		hud.toast("测试装备、灵魂和功勋已放入背包")
	elif OS.is_debug_build() and e.is_action_pressed("debug_restart"):
		play.emit(stage)
