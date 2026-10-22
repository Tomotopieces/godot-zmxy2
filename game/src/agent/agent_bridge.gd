class_name AgentBridge
extends Node
## AI 接入 (agent/ in the repo): a WebSocket client to the local MCP server of zmxy2-remake-mcp. It sends what the player
## can see (`observe`) and the stage's events, and takes input actions and UI presses - nothing else: no stats to set, no
## code to run, no hidden numbers (drop rates, AI states). Off unless a connection string is given: `--agent=<url>` on
## the command line, `?agent=<url>` in the web build's address, or pasted in 设置 (AgentBridge.url, saved in settings.cfg).
##
## Protocol: JSON text messages. Server -> game: {id, op, ...}; game -> server: {id, ok, result | error} for requests and
## {ev, ...} for events. Ops: hello, observe, ui_list, ui_press, input, release_all, speed, pause, screenshot.

const RETRY := 3.0          ## seconds between connection attempts
const MAX_SPEED := 4.0
const SHOT_SCALE := 0.5

static var url := ""        ## the connection string (ws://127.0.0.1:<port>/?t=<token>); "" = off
static var instance: AgentBridge

var _ws := WebSocketPeer.new()
var _state := WebSocketPeer.STATE_CLOSED
var _retry_t := 0.0
var _held := {}             ## action -> true: held by the agent until it lets go
var _taps := {}             ## action -> physics frames left before the tap is released
var _speed := 1.0
var _hud: Label
var _level: Level           ## the level whose signals are connected
var _hp_seen := -1

static func setup(root: Node) -> void:
	if url == "":
		url = _url_from_launch()
	if url == "":
		var cf := ConfigFile.new()
		if cf.load("user://settings.cfg") == OK:
			url = String(cf.get_value("agent", "url", ""))
	instance = AgentBridge.new()
	instance.name = "AgentBridge"
	root.add_child(instance)

## Switch the connection: "" disconnects for good (until set again).
static func set_url(u: String) -> void:
	url = u.strip_edges()
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("agent", "url", url)
	cf.save("user://settings.cfg")
	if instance:
		instance._reconnect()

static func connected() -> bool:
	return instance != null and instance._state == WebSocketPeer.STATE_OPEN

static func _url_from_launch() -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--agent="):
			return a.substr(8)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('agent') || ''", true)
		return String(q) if q != null else ""
	return ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 4 << 20
	var layer := CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	_hud = Label.new()
	_hud.text = "AI 已接入"
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	_hud.position = Vector2(Layers.VIEW.x - 90, 4)
	_hud.visible = false
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	GameState.leveled_up.connect(func(l: int): _send({"ev": "level_up", "level": l}))

func _reconnect() -> void:
	_ws.close()
	_state = WebSocketPeer.STATE_CLOSED
	_retry_t = 0.0
	_release_all()

func _process(delta: float) -> void:
	if url == "":
		_hud.visible = false
		return
	if _state == WebSocketPeer.STATE_CLOSED:
		_retry_t -= delta
		if _retry_t <= 0.0:
			_retry_t = RETRY
			if _ws.connect_to_url(url) == OK:
				_state = WebSocketPeer.STATE_CONNECTING
		return
	_ws.poll()
	var s := _ws.get_ready_state()
	if s != _state:
		_state = s
		if s == WebSocketPeer.STATE_OPEN:
			_send({"ev": "hello", "version": _version(), "role": GameState.role})
		elif s == WebSocketPeer.STATE_CLOSED:
			_release_all()
			_set_speed(1.0)
			_retry_t = RETRY
	_hud.visible = s == WebSocketPeer.STATE_OPEN
	while _ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			_handle(msg)
	_watch_level()

func _physics_process(_delta: float) -> void:
	for a in _taps.keys():
		_taps[a] -= 1
		if _taps[a] <= 0:
			_taps.erase(a)
			if not _held.has(a):
				Input.action_release(a)

static func _version() -> String:
	return MainMenu.version_text()

func _send(d: Dictionary) -> void:
	if _state == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(d))

# ------------------------------------------------------------------ requests

func _handle(m: Dictionary) -> void:
	var id = m.get("id")
	var r = null
	var err := ""
	match String(m.get("op", "")):
		"hello":
			r = {"version": _version()}
		"observe":
			r = observe()
		"ui_list":
			r = ui_list()
		"ui_press":
			err = await ui_press(String(m.get("target", "")))
			r = {"screen": screen_name()}
		"input":
			_input_cmd(m.get("hold", []), m.get("press", []))
			r = true
		"release_all":
			_release_all()
			r = true
		"speed":
			_set_speed(float(m.get("value", 1.0)))
			r = {"speed": _speed}
		"pause":
			r = _pause(bool(m.get("value", true)))
		"screenshot":
			r = await _screenshot(float(m.get("scale", SHOT_SCALE)))
		_:
			err = "unknown op"
	if id != null:
		_send({"id": id, "ok": err == "", "result": r, "error": err})

## The actions the agent may hold or tap: the player's own controls.
const ACTIONS := {"left": &"move_left", "right": &"move_right", "up": &"move_up", "down": &"move_down",
	"attack": &"attack", "jump": &"jump", "skill_u": &"skill_u", "skill_i": &"skill_i", "skill_o": &"skill_o",
	"skill_l": &"skill_l", "rage": &"rage", "treasure": &"treasure", "run": &"run"}
const TAP_FRAMES := 2

func _input_cmd(hold: Array, press: Array) -> void:
	var want := {}
	for h in hold:
		if ACTIONS.has(String(h)):
			want[ACTIONS[String(h)]] = true
	for a in _held.keys():
		if not want.has(a):
			_held.erase(a)
			if not _taps.has(a):
				Input.action_release(a)
	for a in want:
		if not _held.has(a):
			_held[a] = true
			Input.action_press(a)
	for p in press:
		var a: StringName = ACTIONS.get(String(p), &"")
		if a == &"":
			continue
		if _held.has(a) or _taps.has(a):   # a tap of a held key: let go one frame, then press again
			Input.action_release(a)
			await get_tree().physics_frame
		Input.action_press(a)
		_taps[a] = TAP_FRAMES

func _release_all() -> void:
	for a in _held.keys() + _taps.keys():
		Input.action_release(a)
	_held.clear()
	_taps.clear()

func _set_speed(v: float) -> void:
	_speed = clampf(v, 1.0, MAX_SPEED)
	Engine.time_scale = _speed
	Engine.physics_ticks_per_second = int(60 * _speed)   # the physics step stays 1/60 s of game time
	Engine.max_physics_steps_per_frame = maxi(8, int(8 * _speed))

func _pause(on: bool) -> Dictionary:
	var ps := _play_screen()
	if on and ps and not get_tree().paused:
		ps.open_pause()
	elif not on and ps and ps._menu:
		ps._menu.close()
	return {"paused": get_tree().paused}

func _screenshot(scale: float) -> Dictionary:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	scale = clampf(scale, 0.2, 1.0)
	img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	return {"png": Marshalls.raw_to_base64(img.save_png_to_buffer()), "w": img.get_width(), "h": img.get_height()}

# ------------------------------------------------------------------ observation

func _main() -> Node:
	return get_tree().root.get_node_or_null("Main")

func _play_screen() -> PlayScreen:
	var m := _main()
	return m._screen as PlayScreen if m and "_screen" in m else null

## The screen in front, as the player sees it.
func screen_name() -> String:
	var top := _top_layer()
	if top is Cartoon:
		return "cartoon"
	if top is ResultScreen:
		return "result"
	if top is TabMenu or top is ForgeScreen or top is ShopScreen or top is ActivityPanel or top is HelpPanel:
		return "menu"
	if top is SavePanel:
		return "dialog"
	var m := _main()
	if m == null:
		return "loading"
	var s = m._screen
	if s == null:
		return "title"
	if s is SelectRole:
		return "select_role"
	if s is StageMap:
		return "map"
	if s is PlayScreen:
		return "stage"
	if s is Cartoon:
		return "cartoon"
	return "loading"

## The topmost open screen layer (menus, popups, comics, the result).
func _top_layer() -> CanvasLayer:
	var best: CanvasLayer = null
	for l in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var c := l as CanvasLayer
		if not c.visible or c.is_queued_for_deletion() or c.layer >= 99:
			continue
		if not (c is Cartoon or c is ResultScreen or c is TabMenu or c is ForgeScreen or c is ShopScreen \
				or c is ActivityPanel or c is HelpPanel or c is SavePanel or c is SelectRole or c is StageMap or c is MainMenu):
			continue
		if c is MainMenu and not c.get_node("Menu").visible:
			continue
		if best == null or c.layer >= best.layer:
			best = c
	return best

static func _r(v: float) -> float:
	return snappedf(v, 0.1)

func observe() -> Dictionary:
	var o := {"t": _r(Time.get_ticks_msec() / 1000.0), "screen": screen_name(), "speed": _speed,
		"paused": get_tree().paused, "souls": GameState.souls, "merit": GameState.merit}
	var ps := _play_screen()
	if ps == null or ps.level == null or not is_instance_valid(ps.level.hero):
		if GameState.hero_data:
			o["hero"] = {"role": GameState.role, "level": GameState.level}
		return o
	var lv := ps.level
	var h := lv.hero
	o["hero"] = _hero(h)
	var view := Rect2(lv.view_x - 100.0, -200.0, Layers.VIEW.x + 200.0, 1200.0)
	var enemies := []
	for m: Monster in lv.monsters():
		if m.data.is_prop or not m.visible or m.state == Monster.State.DEAD or not view.has_point(m.global_position):
			continue
		var r := m.hurt_rect()
		enemies.append({"uid": m.get_instance_id(), "name": m.data.display_name, "id": m.data.id, "boss": m.data.is_boss,
			"x": _r(m.global_position.x), "y": _r(m.global_position.y),
			"box": [_r(r.position.x), _r(r.position.y), _r(r.size.x), _r(r.size.y)],
			"facing": m.facing, "hp": snappedf(float(m.hp) / maxf(1.0, m.max_hp), 0.001),
			"action": String(m.puppet.action) if m.puppet else "", "hittable": m.can_be_hit()})
	o["enemies"] = enemies
	var props := []
	for m: Monster in get_tree().get_nodes_in_group(&"props"):
		if is_instance_valid(m) and m.visible:
			props.append({"uid": m.get_instance_id(), "name": m.data.display_name, "id": m.data.id,
				"x": _r(m.global_position.x), "y": _r(m.global_position.y)})
	if not props.is_empty():
		o["props"] = props
	var shots := []
	var pickups := []
	for n in lv.world.get_children():
		if n is Projectile and view.has_point(n.global_position):
			shots.append({"x": _r(n.global_position.x), "y": _r(n.global_position.y), "vx": _r(n.velocity.x),
				"vy": _r(n.velocity.y), "hostile": not (n.source is Hero)})
		elif n is GroundItem and not n._taken:
			var d := GameState.item_data(n.item)
			pickups.append({"kind": "item", "name": d.display_name, "quality": d.quality,
				"x": _r(n.global_position.x), "y": _r(n.global_position.y)})
		elif n is Potion and not n._used:
			pickups.append({"kind": "potion", "name": ["小血瓶", "大血瓶", "小蓝瓶"][n.kind],
				"x": _r(n.global_position.x), "y": _r(n.global_position.y)})
	if shots.size() > 24:
		shots.resize(24)
	o["shots"] = shots
	o["pickups"] = pickups
	o["stage"] = _stage(lv, ps)
	return o

func _hero(h: Hero) -> Dictionary:
	var skills := {}
	var keys := ["u", "i", "o", "wj", "l"] if GameState.role == "bajie" else ["u", "i", "o", "l", "wj"]
	var learn: PackedStringArray = GameState.hero_data.learn_active
	for i in learn.size():
		var act := StringName(learn[i])
		var a: AttackData = h.data.attacks.get(act, h.data.attacks.get(StringName(String(act) + "-1")))
		var cost := a.mp_cost if a else 0
		skills[_skill_key(i)] = {"name": String(act), "learned": GameState.has_skill(act), "mp_cost": cost,
			"usable": GameState.has_skill(act) and h.mp >= cost}
	var dbf := []
	for k in h.debuffs._left.keys():
		dbf.append(String(k))
	return {"role": GameState.role, "x": _r(h.global_position.x), "y": _r(h.global_position.y),
		"vx": _r(h.velocity.x), "vy": _r(h.velocity.y), "facing": h.facing, "on_floor": h.is_on_floor(),
		"state": ["move", "attack", "hurt", "dead"][h.state], "action": String(h.puppet.action),
		"hp": h.hp, "hp_max": h.max_hp, "mp": h.mp, "mp_max": h.max_mp,
		"rage": int(h.rage), "rage_max": h.data.rage_max, "transformed": h.transformed,
		"invincible": h.invincible > 0.0 or h._lock_glow, "can_act": h.cooldown <= 0.0 and h.state == Hero.State.MOVE,
		"level": GameState.level, "exp": GameState.exp, "exp_next": GameState.exp_to_next(),
		"skills": skills, "buffs": GameState.buffs.keys(), "debuffs": dbf,
		"treasure": GameState.item_data(GameState.worn[&"treasure"]).display_name if GameState.worn[&"treasure"] else ""}

## Skill slot i (the skill table's row) -> its key on the keyboard.
func _skill_key(i: int) -> String:
	match GameState.role:
		"wukong": return ["wj", "run_j", "u", "i", "o"][i]
		"tangseng": return ["hold_j", "u", "i", "o", "l"][i]
		_: return ["u", "i", "o", "wj", "l"][i]

func _stage(lv: Level, ps: PlayScreen) -> Dictionary:
	var floors := []
	var view := Rect2(lv.view_x - 200.0, -400.0, Layers.VIEW.x + 400.0, 1400.0)
	for body in lv.world.get_node("Layout/Walls").get_children():
		if not body is CollisionObject2D:
			continue
		var oneway := (body as CollisionObject2D).collision_layer & Actor.LAYER_ONEWAY != 0
		for cs in body.get_children():
			if not cs is CollisionShape2D or cs.disabled or cs.shape == null:
				continue
			var r: Rect2 = cs.global_transform * cs.shape.get_rect()
			if r.intersects(view):
				floors.append({"x1": _r(r.position.x), "x2": _r(r.end.x), "y": _r(r.position.y),
					"oneway": oneway or cs.one_way_collision, "h": _r(r.size.y)})
	var d := {"id": "%d-%d" % [ps.stage.x, ps.stage.y], "view_x": _r(lv.view_x), "view_w": Layers.VIEW.x,
		"width": lv.size.x, "room": lv.stop_index, "rooms": lv.stops.size(), "locked": lv.locked,
		"door_open": lv.door_open(), "floors": floors}
	if lv.door_open() and lv.door_zone:
		d["door_x"] = _r(lv.door_zone.global_position.x)
	return d

# ------------------------------------------------------------------ UI

## What can be pressed on the screen in front: the controls the pad can reach there (PadFocus's own scope).
func ui_list() -> Dictionary:
	var scope := _ui_scope()
	var items := []
	if scope == null:
		return {"screen": screen_name(), "items": items}
	var f := get_viewport().gui_get_focus_owner()
	for c in _ui_targets(scope):
		items.append({"id": _ui_id(scope, c), "text": _ui_text(c), "enabled": not (c is BaseButton and c.disabled),
			"focused": c == f})
	var o := {"screen": screen_name(), "items": items}
	if _top_layer() is Cartoon:
		o["hint"] = "comic: ui_press any id or 'next' turns the page"
	return o

func _ui_scope() -> Node:
	for n in get_tree().root.find_children("*", "PadFocus", true, false):
		return n._scope()
	return null

func _ui_targets(scope: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c in PadFocus._targets(scope):
		if not scope.is_in_group(PadFocus.MODAL) and _in_modal(c):
			continue
		out.append(c)
	return out

func _in_modal(c: Control) -> bool:
	for p: Control in get_tree().get_nodes_in_group(PadFocus.MODAL):
		if p.is_visible_in_tree() and p.is_ancestor_of(c):
			return true
	return false

## A stable id: the node path below the screen, with generated names (@TextureRect@123) replaced by their index.
func _ui_id(scope: Node, c: Control) -> String:
	var parts := []
	var n: Node = c
	while n != null and n != scope:
		var nm := String(n.name)
		parts.push_front(("#%d" % n.get_index()) if nm.begins_with("@") else nm)
		n = n.get_parent()
	return "/".join(parts)

func _ui_text(c: Control) -> String:
	if c is ItemIcon:
		var it := _icon_item(c)
		if it:
			var d := GameState.item_data(it)
			var s := "%s[%s]" % [d.display_name, d.quality] if d.quality != "" else d.display_name
			return s + (" x%d" % it.n if it.n > 1 else "") + (" +%d" % it.plus if it.plus > 0 else "")
	if c is Button and c.text != "":
		return c.text.replace("\n", " ")
	for l in c.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and (l as Label).text != "":
			return (l as Label).text.replace("\n", " ")
	return String(c.name)

func _icon_item(c: Control) -> Item:
	for p in [c, c.get_parent()]:
		if p and p.has_meta(&"item"):
			return p.get_meta(&"item")
	return null

## Press a control of the screen in front by its id (or its exact text): the pad's way - focus it, then A.
func ui_press(target: String) -> String:
	if _top_layer() is Cartoon:
		await _tap_ui(&"ui_accept")
		return ""
	var scope := _ui_scope()
	if scope == null:
		return "nothing to press on this screen"
	var hit: Control = null
	var targets := _ui_targets(scope)
	for c in targets:
		if _ui_id(scope, c) == target or _ui_text(c) == target:
			hit = c
			break
	if hit == null:   # the last part of the id alone ("NewGame" for "Menu/NewGame"), when it names one control
		var named := targets.filter(func(c): return _ui_id(scope, c).get_file() == target)
		if named.size() == 1:
			hit = named[0]
	if hit == null:
		return "no such control: " + target
	if hit is BaseButton and hit.disabled:
		return "disabled: " + target
	PadFocus.pad_last = true
	hit.grab_focus()
	await get_tree().process_frame
	await _tap_ui(&"ui_accept")
	await get_tree().create_timer(0.3, true, false, true).timeout   # the press's fades
	return ""

func _tap_ui(a: StringName) -> void:
	for p in [true, false]:
		var e := InputEventAction.new()
		e.action = a
		e.pressed = p
		Input.parse_input_event(e)
		await get_tree().process_frame

# ------------------------------------------------------------------ events

func _watch_level() -> void:
	var ps := _play_screen()
	var lv: Level = ps.level if ps else null
	if lv == _level:
		if lv and is_instance_valid(lv.hero) and lv.hero.hp < _hp_seen:
			_send({"ev": "hurt", "damage": _hp_seen - lv.hero.hp, "hp": lv.hero.hp, "hp_max": lv.hero.max_hp})
		if lv and is_instance_valid(lv.hero):
			_hp_seen = lv.hero.hp
		return
	_level = lv
	_hp_seen = -1
	if lv == null:
		return
	var stage := "%d-%d" % [ps.stage.x, ps.stage.y]
	_send({"ev": "stage_start", "stage": stage})
	lv.boss_spawned.connect(func(m: Monster): _send({"ev": "boss_appear", "name": m.data.display_name}))
	lv.gogo.connect(func(): _send({"ev": "room_clear", "room": lv.stop_index}))
	lv.stage_cleared.connect(func(): _send({"ev": "stage_clear", "stage": stage}))
	lv.ending.connect(func(): _send({"ev": "stage_clear", "stage": stage, "ending": true}))
	lv.hero_died.connect(func(): _send({"ev": "death", "stage": stage}))
	lv.failed.connect(func(): _send({"ev": "stage_fail", "stage": stage}))
	lv.message.connect(func(t: String): _send({"ev": "notice", "text": t}))
	lv.world.child_entered_tree.connect(_on_world_child)

func _on_world_child(n: Node) -> void:
	if n is Monster:
		var m := n as Monster
		m.died.connect(func(_x): if not m.data.is_prop: _send({"ev": "kill", "name": m.data.display_name, "boss": m.data.is_boss}))
	elif n is GroundItem:
		var g := n as GroundItem
		var d := GameState.item_data(g.item)
		_send({"ev": "drop", "name": d.display_name, "quality": d.quality})
		g.tree_exiting.connect(func(): if g._taken: _send({"ev": "pickup", "name": d.display_name, "quality": d.quality}))

## On-screen notices (Toast, which finds the bridge by its path).
func notify_event(ev: Dictionary) -> void:
	_send(ev)
