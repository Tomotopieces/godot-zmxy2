class_name Level
extends Node2D
## One stage built from assets/levels/<name>/level.json: art, walls, camera stops, spawners, exit door.
## Camera follows the original side-scroller rules (ViewControllor): push-scroll at 2/3 screen,
## lock at stop points until their spawns are cleared, then auto-scroll to the next one.

signal stage_cleared
signal hero_died
signal gogo
signal message(text: String)
signal rage_started
signal combo_changed(count: int)
signal boss_spawned(monster: Monster)
signal ending                    ## final boss destroyed: the game is cleared
signal failed                    ## a stage rule lost the stage (2-2 fire timer)
signal transfer(to: Vector2i)    ## hidden stage entrance used: go straight there (MainGame "fbfbfbfb")

static var current: Level

@export var stage := Vector2i(1, 1)
var level_name := "sl11"
@export var scroll_trigger := Layers.VIEW.x * 2.0 / 3.0   ## hero screen x that pushes the camera
@export var back_trigger := 188.0
@export var auto_trigger := 450.0
@export var auto_speed_add := 240.0      ## px/s added to the hero speed while auto-scrolling
@export var auto_speed_max := 720.0
@export var edge_margin := 20.0

var hero: Hero
var world: Node2D
var camera: Camera2D
var view_x := 0.0
var size := Vector2.ZERO
var stops: Array = []        ## [{x, back, spawners: [Spawner], done}]
var stop_index := 0
var locked := false
var auto_scroll := false
var door: Node2D                 ## exit portal (hidden until the stage is cleared); null in hub / ending stages
var door_rect := Rect2()
var walls: Array[AnimatableBody2D] = []   ## scene walls / platforms (meta "wall" = level.json entry)
var params := {}                 ## this stage's script numbers (data/stages.json)
var features: Array = []         ## other scene objects (white-bone door, Xingtian door, fires...) for stage scripts
var script_node: StageScript     ## this stage's special rules (src/level/stages/<level_name>.gd), if any
var fixed_camera := false        ## single-screen boss rooms (5-1, 6-1, 7-1, stage 10)
var debug_boxes := false

var _far: Sprite2D
var _far_width := 0.0
var _can_back := 0.0         ## canBackward: how far the camera may still scroll back (-99: all the way)
var _this_stop_set := false  ## thisStopX != 0: the camera is held at _this_stop_view (where the current room was locked)
var _this_stop_view := 0.0
var _end_x := 0.0     ## right edge the camera may show: the last stop (the art may end before the scene bounds)
var _shake := 0.0
var _freeze_t := 0.0
var _debug: Node2D
var _done := false
var _bosses_killed := 0
## Combo (User.batterNum): hits on monsters; reset when no hit lands between two checks.
const COMBO_CHECK := 20.0 / 24.0
var combo := 0
var best_combo := 0
var _combo_seen := 0
var _combo_t := 0.0

## BGM: bg<stage> for stages 1..7, bg4 beyond (MainGame.newGame).
static func music_for(s: Vector2i) -> String:
	return "bg%d" % (s.x if s.x <= 7 else 4)

static func scene_name(s: Vector2i) -> String:
	return "sl%d%d" % [s.x, s.y]

func _ready() -> void:
	current = self
	level_name = scene_name(stage)
	var all = JSON.parse_string(FileAccess.get_file_as_string("res://data/stages.json"))
	params = all.get(level_name, {}) if all is Dictionary else {}
	process_physics_priority = 10   # after the actors moved
	_build(JSON.parse_string(FileAccess.get_file_as_string("res://assets/levels/%s/level.json" % level_name)))
	hero = Hero.create()
	hero.position = Vector2(200, 200)
	hero.died.connect(func(_h): hero_died.emit())
	world.add_child(hero)
	_debug = Node2D.new()
	_debug.z_index = Layers.Z_DEBUG
	_debug.draw.connect(_draw_debug)
	world.add_child(_debug)
	Snd.music(music_for(stage))
	fixed_camera = params.get("fixed_camera", false)
	if params.get("save_on_enter", false):
		GameState.autosave()
	if params.has("auto_touch"):
		# boss rooms: the first stop is touched after a delay, wherever the camera is
		get_tree().create_timer(float(params.auto_touch), false).timeout.connect(_touch_stop)
	var sp := "res://src/level/stages/%s.gd" % level_name
	if ResourceLoader.exists(sp):
		script_node = load(sp).new()
		script_node.level = self
		script_node.p = params
		add_child(script_node)
		script_node.setup()

func _exit_tree() -> void:
	if current == self:
		current = null
		DamageNumber.clear_pool()

## Spawned objects start where they were placed (no interpolation from a stale transform).
func add_object(n: Node) -> void:
	world.add_child(n)
	n.reset_physics_interpolation()

func monsters() -> Array:
	return get_tree().get_nodes_in_group(&"monsters")

func heroes() -> Array:
	return [hero] if is_instance_valid(hero) else []

## What an actor's attacks can hit: heroes hit monsters and props (hub selector / stones), monsters hit heroes.
func enemies_of(a: Actor) -> Array:
	return monsters() + get_tree().get_nodes_in_group(&"props") if a is Hero else heroes()

## A hittable scene object that is not a monster to clear (10-1 selector and stones).
func add_prop(m: Monster) -> void:
	m.add_to_group(&"props")
	add_object(m)

func view_rect() -> Rect2:
	return Rect2(Vector2(view_x, 0), Layers.VIEW)

## Short notice for the HUD (item picked up, bag full...).
func toast(text: String) -> void:
	message.emit(text)

# ------------------------------------------------------------------ stage scripts

## Script hooks that monsters call (4-1 platforms, 10-1 selector).
func start_final_platforms() -> void:
	if script_node:
		script_node.call("start_final_platforms")

func hub_pointer_changed(prop: Monster, pointer: int) -> void:
	if script_node and script_node.has_method("hub_pointer_changed"):
		script_node.call("hub_pointer_changed", prop, pointer)

## Hidden-stage entrance used (white-bone door, Xingtian door, aurora, hub doors).
func go_to(to: Vector2i) -> void:
	if _done:
		return
	_done = true
	transfer.emit(to)

## A stage rule lost the stage.
func fail() -> void:
	if _done:
		return
	_done = true
	failed.emit()

## Hidden walls (isHideWall) become solid (3-3: 孟婆 closes the arena).
func enable_hidden_walls() -> void:
	for b in walls:
		if b.get_meta(&"wall").kind == "hidden":
			(b.get_child(0) as CollisionShape2D).set_deferred(&"disabled", false)

func _touch_stop() -> void:
	if stop_index < stops.size() and not locked:
		locked = true
		auto_scroll = false
		_this_stop_set = true
		_this_stop_view = view_x
		_can_back = float(stops[stop_index].back) - Layers.VIEW.x

## The last boss is gone: no exit portal, the ending plays.
func final_victory() -> void:
	_done = true
	ending.emit()

func door_open() -> bool:
	return door != null and door.visible

func open_door() -> void:
	if door:
		door.visible = true

func close_door() -> void:
	if door:
		door.visible = false

func add_combo_hit() -> void:
	combo += 1
	best_combo = maxi(best_combo, combo)
	combo_changed.emit(combo)

func shake(px: float) -> void:
	_shake = px

## Short hit-stop (rage transform).
## Rage transform: the world freezes while the full-screen transform animation plays (MainGame.stopGame).
func rage_transform(seconds: float) -> void:
	rage_started.emit()
	freeze(seconds)

func freeze(seconds: float) -> void:
	_freeze_t = seconds
	get_tree().paused = true
	var tree := get_tree()
	await tree.create_timer(seconds, true, false, true).timeout
	tree.paused = false

# ------------------------------------------------------------------ build

func _xf(m: Array, info: Dictionary) -> Transform2D:
	var t := Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
	var s := 1.0 / float(info.scale)
	return t * Transform2D(Vector2(s, 0), Vector2(0, s), Vector2(info.ox, info.oy))

func _build(d: Dictionary) -> void:
	size = Vector2(d.size[0], d.size[1])
	var far_layer := CanvasLayer.new()
	far_layer.layer = -1
	add_child(far_layer)
	_far = Sprite2D.new()
	_far.centered = false
	_far.texture = load(d.textures[d.far.tex].res)
	_far_width = _far.texture.get_width()
	far_layer.add_child(_far)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var art := Node2D.new()
	art.name = "Art"
	art.z_index = Layers.Z_ART
	world.add_child(art)
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.z_index = Layers.Z_GROUND
	world.add_child(ground)
	for leaf in d.art:
		var info: Dictionary = d.textures[leaf[0]]
		var sp := Sprite2D.new()
		sp.centered = false
		sp.texture = load(info.res)
		sp.transform = _xf(leaf[1], info)
		if leaf[2] != null:
			var ct: Array = leaf[2]
			sp.modulate = Color(ct[0] + ct[4] / 255.0, ct[1] + ct[5] / 255.0, ct[2] + ct[6] / 255.0, clampf(ct[3] + ct[7] / 255.0, 0, 1))
		(ground if leaf.size() > 3 and leaf[3] == 1 else art).add_child(sp)

	for w in d.walls:
		var body := AnimatableBody2D.new()   # static unless a stage script moves it
		body.z_index = Layers.Z_MECHANISM            # art a stage script hangs on it (boat, platforms)
		body.sync_to_physics = false         # scripts move it directly in the physics step
		body.set_meta(&"wall", w)
		walls.append(body)
		var oneway: bool = w.kind == "oneway"
		body.collision_layer = Actor.LAYER_ONEWAY if oneway else Actor.LAYER_WORLD
		body.collision_mask = 0
		body.position = Vector2(w.pos[0], w.pos[1] + _slope_drop(w, d.walls))
		body.rotation_degrees = w.rot
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(w.size[0], w.size[1])
		cs.shape = rs
		cs.one_way_collision = oneway
		cs.disabled = w.kind == "hidden"
		body.add_child(cs)
		world.add_child(body)

	var sorted: Array = d.stops.duplicate()
	sorted.sort_custom(func(a, b): return a.x < b.x)
	for s in sorted:
		stops.append({"x": float(s.x), "back": float(s.back), "spawners": [], "done": false})
	_end_x = minf(size.x, float(stops[-1].x)) if not stops.is_empty() else size.x
	_close_edge_slivers(art)
	_close_edge_slivers(ground)
	for sp in d.spawners:
		var md := monster_data(int(sp.enemy))
		if md == null:
			push_warning("%s: no data for monster %d" % [level_name, sp.enemy])
			continue
		if sp.get("boss", false) and not md.is_boss:
			md = md.duplicate()
			md.is_boss = true
		var spawner := Spawner.new(md, Vector2(sp.x, sp.y), sp.delay, sp.interval, sp.total)
		if int(sp.stop) < stops.size():
			stops[int(sp.stop)].spawners.append(spawner)

	for dd in d.doors:
		if dd.kind != "exit_door":
			features.append(dd)
			continue
		door = Rig.create("exit_door")
		door.z_index = Layers.Z_MECHANISM
		door.position = Vector2(dd.pos[0], dd.pos[1])
		door.visible = false
		world.add_child(door)
		door.play(door.actions[0])
		door_rect = Rect2(dd.rect[0], dd.rect[1], dd.rect[2], dd.rect[3])

	_warm_rigs(d)
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS   # moved in physics, interpolated for display
	world.add_child(camera)
	camera.make_current()

## The original walks a hero over the joint of a slope and the flat ground above it; a physics body would be stopped by
## the corner of the slope's end cap that pokes a pixel or two above that ground (奈何桥: no way back down). Such a slope
## is lowered until its top corner is level with the ground.
const SLOPE_BUMP := 6.0

## How far a sloped wall `w` has to be lowered to be level with the ground it ends at (0 for everything else).
func _slope_drop(w: Dictionary, all: Array) -> float:
	var rot := absf(fmod(float(w.rot), 90.0))
	if w.kind != "solid" or rot < 1.0 or rot > 89.0:
		return 0.0
	var half := Vector2(w.size[0], w.size[1]) / 2.0
	var xf := Transform2D(deg_to_rad(float(w.rot)), Vector2(w.pos[0], w.pos[1]))
	var top := Vector2.ZERO
	var found := false
	for c in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		var p: Vector2 = xf * c
		if not found or p.y < top.y:
			top = p
			found = true
	for o in all:
		if o == w or o.kind != "solid" or absf(float(o.rot)) > 0.5:
			continue
		var r := Rect2(Vector2(o.pos[0] - o.size[0] / 2.0, o.pos[1] - o.size[1] / 2.0), Vector2(o.size[0], o.size[1]))
		if top.x >= r.position.x and top.x <= r.end.x and r.position.y > top.y and r.position.y - top.y <= SLOPE_BUMP:
			return r.position.y - top.y
	return 0.0

## Common effects plus every rig of this stage's monsters (body, projectiles, and rigs named after the body:
## bullets, effects, form clips) load in the background while the stage starts.
const WARM_COMMON := ["fx_monster_hurt1", "fx_monster_hurt2", "fx_hero_hurt", "orb_Red", "orb_Green", "orb_Blue",
	"orb_While", "potion_BigHP", "potion_SmallHP", "potion_SmallMP", "gogo", "fx_levelup"]

func _warm_rigs(d: Dictionary) -> void:
	var bodies := {}
	for sp in d.spawners:
		var md := monster_data(int(sp.enemy))
		if md:
			bodies[md.rig] = true
			for a: AttackData in md.attacks.values():
				if a.projectile != "":
					bodies[a.projectile] = true
	var names: Array = WARM_COMMON.duplicate()
	var all := DirAccess.get_directories_at("res://assets/rigs")
	for b in bodies:
		for r in all:
			if r == b or r.begins_with(b):
				names.append(r)
	Rig.warm(names)

## Some stages' art stops a few pixels short of the playable view (5-3: 4 px at the left, 1 px under the floor),
## letting the far background show as a thin line. Pieces spanning the view whose edge falls just inside it are
## stretched by those few pixels to reach the edge.
const EDGE_SLIVER := 6.0

func _close_edge_slivers(art: Node2D) -> void:
	for sp: Sprite2D in art.get_children():
		var r: Rect2 = sp.transform * Rect2(Vector2.ZERO, sp.texture.get_size())
		if r.size.x < Layers.VIEW.x:
			continue
		var grow := Rect2(r)
		if r.position.x > 0.0 and r.position.x <= EDGE_SLIVER:
			grow = grow.expand(Vector2(0.0, r.position.y))
		if r.end.x < _end_x and r.end.x >= _end_x - EDGE_SLIVER:
			grow = grow.expand(Vector2(_end_x, r.position.y))
		if r.end.y < Layers.VIEW.y and r.end.y >= Layers.VIEW.y - EDGE_SLIVER:
			grow = grow.expand(Vector2(r.position.x, Layers.VIEW.y))
		if grow != r:
			# map the old rect onto the grown one (a tiny stretch, invisible on art this size)
			var k := grow.size / r.size
			sp.transform = Transform2D(0.0, k, 0.0, grow.position - r.position * k) * sp.transform

## Monster numbers for this scene (a scene may make a monster its boss with different stats).
func monster_data(id: int) -> MonsterData:
	for p in ["res://data/monsters/monster_%d_%s.tres" % [id, level_name], "res://data/monsters/monster_%d.tres" % id]:
		if ResourceLoader.exists(p):
			return load(p)
	return null

# ------------------------------------------------------------------ flow

func _physics_process(delta: float) -> void:
	if not is_instance_valid(hero):
		return
	_update_stops(delta)
	_update_camera(delta)
	GameState.tick_buffs(delta)
	_combo_t += delta
	if _combo_t >= COMBO_CHECK:
		_combo_t = 0.0
		best_combo = maxi(best_combo, combo)
		if _combo_seen == combo:
			combo = 0
		_combo_seen = combo
	var up := Input.is_action_just_pressed("move_up")
	if up and script_node and not _done and script_node.on_up(hero):
		up = false
	if door_open() and not _done and up and door_rect.has_point(hero.global_position):
		_done = true
		Snd.stop_music()
		hero.controls_locked = true   # the keyboard is released while the scene fades out
		stage_cleared.emit()
	if debug_boxes:
		_debug.queue_redraw()

func _unhandled_input(e: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if e.is_action_pressed("debug_toggle_boxes"):
		debug_boxes = not debug_boxes
		_debug.queue_redraw()
	elif e.is_action_pressed("debug_kill_all"):
		# test helper: every monster on the level dies (a boss with more forms goes to its next one)
		for m: Monster in monsters():
			if m.can_be_hit():
				m.damage_directly(maxi(m.hp, 1))
	elif e.is_action_pressed("debug_refill") and is_instance_valid(hero):
		hero.refill()
		hero.rage = hero.data.rage_max

func _update_stops(delta: float) -> void:
	if stop_index >= stops.size():
		return
	var s: Dictionary = stops[stop_index]
	if not locked:
		return   # the camera touches a stop (_update_camera) when the hero pushes it into the window
	var busy := false
	var fb: bool = params.get("fb", false)   # dungeon (9-1): spawners only fill an empty screen
	for sp: Spawner in s.spawners:
		if not fb or monsters().is_empty():
			sp.tick(delta, self)
		busy = busy or not sp.finished()
	if busy or not monsters().is_empty():
		return
	locked = false
	s.done = true
	stop_index += 1
	if stop_index < stops.size() and not fixed_camera:   # a fixed-camera room has nowhere to go on to
		auto_scroll = true
		gogo.emit()
	elif not _has_boss_spawner():
		open_door()   # stages without a boss open as soon as the last stop is cleared

func _has_boss_spawner() -> bool:
	for s in stops:
		for sp: Spawner in s.spawners:
			if sp.data.is_boss:
				return true
	return false

## Every monster enters the level here (spawners, summons, form changes).
func add_monster(m: Monster) -> void:
	m.add_to_group(&"monsters")
	add_object(m)
	if m.data.is_boss:
		boss_spawned.emit(m)
	if script_node:
		script_node.on_monster_added(m)

## A boss finished dying: the exit opens once no other boss is left (Monster33/34 share a room).
func boss_destroyed(m: Monster) -> void:
	_bosses_killed += 1
	var merit := Forge.reward_merit(m.data.id)
	if merit > 0:
		toast("获得 功勋 + %d" % merit)
	for o in monsters():
		if o != m and o.data.is_boss and o.state != Monster.State.DEAD:
			return
	open_door()

## ViewControllor.step, in px per tick (the original's speed.x is the hero's speed per frame):
##  - the hero's left edge past 2/3 of the screen pushes the camera by the hero's speed; the first push that leaves
##    the next stop in the touch window (900..980 from the left) locks the room there; with no stop left it goes on
##    to the last stop + 70 px
##  - the hero's left edge at or before 188 scrolls it back by the hero's speed, while canBackward allows
##  - after a room is cleared the auto camera runs: hero speed + 10 px/frame (at most 30) until the hero is at 450,
##    or the next stop is within 880..1000 of the screen's left
func _update_camera(delta: float) -> void:
	if fixed_camera:
		camera.position = Vector2(0, 0)
		camera.offset.x = _shake
		_shake = 0.0
		return
	var speed := hero.velocity.x * delta
	var has_stop := stop_index < stops.size()
	var stop: Dictionary = stops[stop_index] if has_stop else {}
	var stop_sx: float = float(stop.x) - view_x if has_stop else 0.0   # its screen x before this tick's scrolling
	var held := _this_stop_set
	var held_view := _this_stop_view
	if not has_stop:
		held = true
		held_view = float(stops[-1].x) - 870.0 if not stops.is_empty() else -870.0
	var left := hero.hurt_rect().position.x - view_x
	if left >= scroll_trigger:
		var s := maxf(speed, 0.0)
		if held and view_x < held_view:
			view_x += s
			if _can_back != -99.0:
				_can_back += s
		elif has_stop and not locked:
			view_x += s
			_can_back += s
			if stop_sx >= 900.0 and stop_sx <= 980.0:
				_can_back = float(stop.back) - Layers.VIEW.x
				_this_stop_set = true
				_this_stop_view = view_x
				locked = true
				auto_scroll = false
			else:
				_can_back = -99.0
				_this_stop_set = false
	elif left <= back_trigger and (_can_back > 0.0 or _can_back == -99.0):
		var s := minf(speed, 0.0)
		if view_x + s >= 0.0:
			view_x += s
			if _can_back > 0.0:
				_can_back += s
	if auto_scroll and has_stop:
		if hero.global_position.x - view_x > auto_trigger:
			view_x += minf(absf(hero.velocity.x) + auto_speed_add, auto_speed_max) * delta
		else:
			auto_scroll = false
		if stop_sx >= 880.0 and stop_sx <= 1000.0:
			auto_scroll = false
	view_x = clampf(view_x, 0.0, maxf(size.x - Layers.VIEW.x, 0.0))
	camera.position = Vector2(view_x, 0)
	camera.offset.x = _shake
	_shake = 0.0
	if _end_x > Layers.VIEW.x:
		_far.position.x = -view_x * (_far_width - Layers.VIEW.x) / (_end_x - Layers.VIEW.x)

func _draw_debug() -> void:
	if not debug_boxes:
		return
	var actors: Array = monsters() + heroes()
	for a: Actor in actors:
		_debug.draw_rect(a.hurt_rect(), Color(0, 1, 0, 0.8), false, 1.0)
		var r := a.rig.hit_rect()
		if r.size != Vector2.ZERO:
			_debug.draw_rect(r, Color(1, 0, 0, 0.8), false, 1.0)
	for p in world.get_children():
		if p is Projectile:
			var r: Rect2 = p.rig.hit_rect()
			if r.size != Vector2.ZERO:
				_debug.draw_rect(r, Color(1, 0.5, 0, 0.8), false, 1.0)
	if door:
		_debug.draw_rect(door_rect, Color(0, 0.5, 1, 0.8), false, 1.0)