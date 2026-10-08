class_name SaveGame
extends RefCounted
## Save slots (user://slot_N.json) of the GameState profile: serialising, atomic writes with a .bak, versioning and
## validated loading. GameState keeps the one-line entry points (save_to, load_from, slot_info, autosave).

const SLOT_FILE := "user://slot_%d.json"
const VERSION := 1

static func to_dict(g: Node) -> Dictionary:
	var w := {}
	for k in g.worn:
		w[String(k)] = g.worn[k].to_dict() if g.worn[k] else {}
	return {
		"version": VERSION,
		"level": g.level, "exp": g.exp, "souls": g.souls, "attack": g.attack,
		"skills": g.skills.keys().filter(func(k): return g.skills[k]).map(func(k): return String(k)),
		"passives": g.passives,
		"bag": g.bag.map(func(it: Item): return it.to_dict()), "worn": w,
		"stage": [g.stage.x, g.stage.y], "progress": [g.progress.x, g.progress.y],
		"opening_seen": g.opening_seen, "hhe_seen": g.hhe_seen, "buffs": g.buffs,
		"merit": g.merit, "merit_day": g.merit_day, "merit_times": g.merit_times,
		"title": "Lv.%d  悟空  %d-%d" % [g.level, g.progress.x, g.progress.y],
		"datetime": Time.get_datetime_string_from_system(false, true),
	}

## Written to a temporary file and renamed over the slot (a crash mid-write cannot truncate it); the previous slot is
## kept as <slot>.bak, which reading falls back to when the slot cannot be parsed.
static func write(i: int, d: Dictionary) -> bool:
	var path: String = SLOT_FILE % i
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("save: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("save: cannot replace %s" % path)
		return false
	return true

## The parsed save of a slot (falling back to its backup), {} when empty or unreadable.
static func read(i: int) -> Dictionary:
	for path in [SLOT_FILE % i, (SLOT_FILE % i) + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
			return _migrate(json.data)
		push_warning("save: %s is not readable" % path)
	return {}

## Brings an older save up to VERSION (version 0 = written before the field existed; same layout).
static func _migrate(d: Dictionary) -> Dictionary:
	d["version"] = VERSION
	return d

## {title, datetime} of a slot, or {} when empty.
static func info(i: int) -> Dictionary:
	var d := read(i)
	return {"title": str(d.get("title", "")), "datetime": str(d.get("datetime", ""))} if not d.is_empty() else {}

static func _pair(v: Variant, fallback: Vector2i) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1])) if v is Array and v.size() >= 2 else fallback

## Applies a read save to the profile `g` (already reset by the caller), validating and clamping every field.
static func apply(g: Node, d: Dictionary) -> void:
	var hero: HeroData = g.hero_data
	g.level = clampi(int(d.get("level", 1)), 1, hero.level_max)
	g.exp = maxi(int(d.get("exp", 0)), 0)
	g.souls = maxi(int(d.get("souls", 0)), 0)
	g.attack = maxi(int(d.get("attack", hero.attack_power(g.level))), 0)
	for s in d.get("skills", []):
		if s is String:
			g.skills[StringName(s)] = true
	var pv = d.get("passives", [])
	if pv is Array:
		for n in mini(pv.size(), g.passives.size()):
			g.passives[n] = clampi(int(pv[n]), 0, hero.passive_max)
	g.bag.clear()
	for it in d.get("bag", []) if d.get("bag") is Array else []:
		var clean := Item.from_dict(it)
		if clean:
			g.bag.append(clean)
	var w = d.get("worn", {})
	for k in g.worn:
		g.worn[k] = Item.from_dict(w.get(String(k))) if w is Dictionary else null
	g.stage = _pair(d.get("stage"), Vector2i(1, 1))
	g.progress = _pair(d.get("progress"), Vector2i(1, 1))
	g.opening_seen = d.get("opening_seen", true) == true
	g.hhe_seen = d.get("hhe_seen", false) == true
	g.merit = maxi(int(d.get("merit", 0)), 0)
	g.merit_day = str(d.get("merit_day", ""))
	g.merit_times = maxi(int(d.get("merit_times", 0)), 0)
	var bf = d.get("buffs", {})
	if bf is Dictionary:
		for b in bf:
			if EquipmentCatalog.get_catalog().buffs.has(b) and (bf[b] is float or bf[b] is int):
				g.buffs[b] = float(bf[b])
