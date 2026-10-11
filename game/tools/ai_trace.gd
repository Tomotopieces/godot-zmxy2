extends Node
## Deterministic AI behaviour traces: every monster is fought alone in the debug boss arena with the hero standing still at
## a near / middle / far distance, and what its brain does (state, action, form, spawns, deaths) is written down frame by
## frame. A refactor of the AI must leave the traces unchanged - the baselines live in tools/ai_traces/.
##
##   godot --headless --path game --fixed-fps 60 res://tools/ai_trace.tscn -- [--ids=45,58] [--secs=60] [--out=<dir>] [--check]
##
## --out writes <dir>/<id>.txt (default: the baseline folder); --check compares with the baselines instead of writing and
## prints "FAIL <id>: ..." for every monster whose trace differs. The run is made deterministic by Rng.seed_with, a fixed
## frame rate and a hero that does not move (its position and health are reset every tick).

const BASELINE := "res://tools/ai_traces"
const BANDS := {"near": 90.0, "mid": 300.0, "far": 650.0}   ## hero distance to the boss, px
const BOSS_X := 833.45
const HERO_Y := 473.6
const HIT_EVERY := 3.0      ## s: every boss unit loses a fifth of its health (forms, revives, deaths show up in the trace)
const SEED := 20111009

var _lines: PackedStringArray
var _frame := 0
var _t0 := -1               ## frame of the first monster's appearance: the trace counts from there (the first fight of a
                            ## process loads its resources one frame later than the others)
var _band_x := 0.0
var _seen := {}             ## instance id of a Monster -> index of its appearance
var _last := {}             ## index -> last recorded "state/action"
var _hero: Hero
var _running := false
var _secs := 75.0

func _ready() -> void:
	var ids: Array[int] = []
	var out := ""
	var check := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			for s in a.substr(6).split(","):
				ids.append(int(s))
		elif a.begins_with("--secs="):
			_secs = a.substr(7).to_float()
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--check":
			check = true
	if ids.is_empty():
		for i in range(30, 82):
			ids.append(i)
	var failed := 0
	for id in ids:
		var text := ""
		for band in BANDS:
			text += "# %d %s\n" % [id, band]
			text += await _run(id, band)
		if check:
			var base := FileAccess.get_file_as_string("%s/%d.txt" % [BASELINE, id]).replace("\r\n", "\n")   # (git may check the baselines out with CRLF)
			if base != text:
				failed += 1
				print("FAIL %d: trace differs from the baseline (%s)" % [id, _first_diff(base, text)])
		else:
			var dir := out if out != "" else ProjectSettings.globalize_path(BASELINE)
			DirAccess.make_dir_recursive_absolute(dir)
			var f := FileAccess.open("%s/%d.txt" % [dir, id], FileAccess.WRITE)
			f.store_string(text)
			f.close()
	print("ai_trace: %d monsters, %d differ" % [ids.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)

func _first_diff(a: String, b: String) -> String:
	var la := a.split("\n")
	var lb := b.split("\n")
	for i in maxi(la.size(), lb.size()):
		var x: String = la[i] if i < la.size() else "<end>"
		var y: String = lb[i] if i < lb.size() else "<end>"
		if x != y:
			return "line %d: baseline '%s' / now '%s'" % [i + 1, x, y]
	return "no difference"

## One fight: returns the trace of this monster at this distance.
func _run(id: int, band: String) -> String:
	GameState.new_game("wukong")
	Rng.seed_with(SEED + id)
	Level.arena_boss = load("res://data/monsters/monster_%d.tres" % id)
	var ps := PlayScreen.create(Level.ARENA)
	add_child(ps)
	_lines = PackedStringArray()
	_seen.clear()
	_last.clear()
	_frame = 0
	_t0 = -1
	_hero = null
	_band_x = BOSS_X - float(BANDS[band])
	_running = true
	var frames := int(_secs * 60.0)
	while (_t0 < 0 or _frame - _t0 < frames) and _frame < frames + 600:
		await get_tree().physics_frame
	_running = false
	ps.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return "\n".join(_lines) + "\n"

func _physics_process(_delta: float) -> void:
	if not _running:
		return
	_frame += 1
	var lv := Level.current
	if lv == null or not is_instance_valid(lv.hero):
		return
	if _hero == null:
		_hero = lv.hero
		_hero.max_hp = 1000000
	_hero.hp = _hero.max_hp
	_hero.controls_locked = true
	_hero.global_position = Vector2(_band_x, HERO_Y)
	_hero.velocity = Vector2.ZERO
	for m: Monster in lv.monsters():
		var oid := m.get_instance_id()
		if _t0 < 0:
			_t0 = _frame
		if not _seen.has(oid):
			_seen[oid] = _seen.size()
			_lines.append("%d #%d appears id=%d hp=%d x=%d" % [_frame - _t0, _seen[oid], m.data.id, m.hp, m.global_position.x])
		var n: int = _seen[oid]
		var key := "%s/%s/%d" % [Monster.State.keys()[m.state], m.rig.action, m.max_hp]
		if _last.get(n, "") != key:
			_last[n] = key
			_lines.append("%d #%d %s hp=%d/%d dx=%d" % [_frame - _t0, n, key.get_slice("/", 0) + "/" + key.get_slice("/", 1), m.hp, m.max_hp, m.global_position.x - _band_x])
	for oid: int in _seen:
		var n: int = _seen[oid]
		var obj := instance_from_id(oid) as Monster
		if (obj == null or obj.is_queued_for_deletion()) and _last.get(n, "") != "gone":
			_last[n] = "gone"
			_lines.append("%d #%d gone" % [_frame - _t0, n])
	if _t0 >= 0 and (_frame - _t0) % int(HIT_EVERY * 60.0) == 0:
		for m: Monster in lv.monsters():
			if m.data.is_boss and m.can_be_hit():
				m.damage_directly(maxi(1, m.max_hp / 5))
