extends SceneTree
## Bake the raw original numbers (tools/data/*.json, frames & px/frame) into Godot resources in px / seconds.
##
##   godot --headless --path game -s res://tools/bake_data.gd
##
## The frame rate comes from the SWF header recorded in each rig.json, so no game code ever sees it.

const OUT := "res://data"

var _fps := 0.0

func _init() -> void:
	var src := ProjectSettings.globalize_path("res://").path_join("../tools/data")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/monsters"))
	for role in ["wukong", "tangseng", "bajie"]:
		_bake_hero(_json(src.path_join("%s.json" % role)), role)
	_bake_monsters(_json(src.path_join("monsters.json")), _json(src.path_join("monsters_auto.json")))
	_bake_equipment(_json(src.path_join("equipment.json")))
	_bake_stages(_json(src.path_join("stages.json")))
	quit()

## Stage script numbers, units converted, as plain JSON (res://data/stages.json).
func _bake_stages(d: Dictionary) -> void:
	_fps = _rig_fps("wukong")
	var out := {}
	for k in d:
		if not k.begins_with("_"):
			out[k] = _units(d[k])
	var f := FileAccess.open(OUT + "/stages.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "	"))
	print("baked ", OUT + "/stages.json")

## aStrengthen field names -> our stat names
const STRENGTHEN_KEYS := {"att": "atk", "ehp": "hp_regen", "emp": "mp_regen", "ebol": "lifesteal", "dhit": "deephit"}

func _bake_equipment(d: Dictionary) -> void:
	_fps = _rig_fps("wukong")
	var c := EquipmentCatalog.new()
	var r: Dictionary = d.rules
	c.regen_interval = _sec(r.regen_frames)
	c.bag_size = r.bag_size
	c.ground_life = _sec(r.ground_frames)
	c.boss_loot = PackedStringArray(r.boss_loot)
	c.buff_time = _sec(r.buff_frames)
	c.use = r.use
	c.buffs = r.buffs
	c.drop_bonus = r.drop_bonus
	c.stone_drop = r.stone_drop
	c.tabs = r.tabs
	c.unique = PackedStringArray(r.unique)
	c.strengthen = r.strengthen
	c.fusion = r.fusion
	c.treasures = r.treasures
	c.shop = r.shop
	c.revive = {"item": r.revive.item, "invincible": _sec(r.revive.invincible_frames), "ratio": r.revive.ratio, "max_y": r.revive.max_y}
	for id in d.items:
		var e: Dictionary = d.items[id]
		var q := EquipmentData.new()
		q.id = StringName(id)
		q.display_name = e.name
		q.type = StringName(e.type)
		q.user = e.user
		q.show = int(e.show)
		q.quality = e.quality
		q.value = int(e.get("value", 0))
		q.color = Color(e.color)
		q.desc = e.desc
		q.stone = int(e.get("stone", 0))
		q.charm = StringName(e.get("charm", ""))
		for k in e.get("strengthen", {}):
			q.strengthen[STRENGTHEN_KEYS.get(k, k)] = float(e.strengthen[k])
		for k in e.stats:
			var v = e.stats[k]
			q.stats[StringName(k)] = Vector2(v[0], v[1]) if v is Array else Vector2(v, v)
		var icon := "res://assets/items/%s.png" % id
		var ground := "res://assets/items/fall_%s.png" % id
		q.icon = load(icon) if ResourceLoader.exists(icon) else null
		q.ground_icon = load(ground) if ResourceLoader.exists(ground) else q.icon
		c.items[q.id] = q
	_save(c, EquipmentCatalog.PATH)

func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(d is Dictionary, "bad json " + path)
	return d

func _rig_fps(rig: String) -> float:
	return float(_json(ProjectSettings.globalize_path("res://assets/rigs/%s/rig.json" % rig)).fps)

func _sec(frames) -> float:
	return float(frames) / _fps

func _pps(px_per_frame) -> float:
	return float(px_per_frame) * _fps

## Launch speed whose continuous arc reaches the same apex as the original per-frame integration
## (y += vy; vy += g), so jump height matches exactly.
func _jump_velocity(jump_power: float, g_frame: float, g_sec: float) -> float:
	var vy := jump_power
	var h := 0.0
	while vy < 0.0:
		h -= vy
		vy += g_frame
	return -sqrt(2.0 * g_sec * h)

func _attack(a: Dictionary) -> AttackData:
	var r := AttackData.new()
	r.power_mul = float(a.get("power", 0.0 if a.has("flat") else 1.0))
	r.flat = int(a.get("flat", 0))
	r.kind = {"physics": AttackData.Kind.PHYSICS, "magic": AttackData.Kind.MAGIC}.get(a.get("kind", ""), AttackData.Kind.TRUE)
	var kb: Array = a.get("knockback", [0, 0])
	r.knockback = Vector2(_pps(kb[0]), _pps(kb[1]))
	r.push_from_center = a.get("push_from_center", false)
	var interval := int(a.get("interval", 0))
	r.rehit_interval = 0.0 if interval >= 999 else _sec(interval)
	r.max_hits = int(a.get("max_hits", 1))
	r.mp_cost = int(a.get("mp", 0))
	r.cooldown = _sec(a.get("cooldown", 0))
	r.dash_speed = _pps(a.get("dash_speed", 0))
	r.rage_dash_speed = _pps(a.get("rage_dash_speed", 0))
	r.invincible = _sec(a.get("invincible", 0))
	# BaseAddEffect: poison ticks every 24 frames for "power"
	for e in a.get("add_effect", []):
		r.effects.append({"name": e.name, "time": _sec(e.get("time", 0)), "power": e.get("power", 0), "tick": _sec(24)})
	if a.has("spawn"):
		var s: Dictionary = a.spawn
		r.projectile = s.scene
		r.spawn_offset = Vector2(s.offset[0], s.offset[1])
		r.speed = _pps(s.get("speed", 0))
		r.distance = float(s.get("distance", 0))
		r.spin_deg = float(s.get("spin_deg", 0))
		r.spin_time = float(s.get("spin_ms", 0)) / 1000.0
	return r

func _bake_hero(d: Dictionary, rig: String) -> void:
	_fps = _rig_fps(rig)
	var m: Dictionary = d.move
	var h := HeroData.new()
	h.rig = rig
	var meta: Dictionary = d.meta
	h.role = meta.role
	h.role_index = int(meta.index)
	h.title = meta.title
	h.character = meta.character
	h.sound_prefix = meta.sound_prefix
	h.super_armor_in_rage = meta.super_armor_in_rage
	h.damage_taken_mul_in_rage = float(meta.damage_taken_mul_in_rage)
	h.lock_glow = Color(meta.lock_glow)
	h.kit = _units(d.get("kit", {}))
	h.walk_speed = _pps(m.walk_speed)
	h.run_speed = _pps(m.run_speed)
	h.gravity = _pps(_pps(m.gravity))
	h.jump_velocity = _jump_velocity(m.jump_power, m.gravity, h.gravity)
	h.rage_gravity = _pps(_pps(m.rage_gravity))
	h.rage_jump_velocity = _jump_velocity(m.jump_power * m.rage_jump_mul, m.rage_gravity, h.rage_gravity)
	h.rage_speed_mul = m.rage_speed_mul
	h.double_tap_window = m.double_tap_ms / 1000.0
	h.drop_through = m.drop_through_px
	h.spawn_invincible = _sec(m.spawn_invincible_frames)
	var s: Dictionary = d.stats
	for k in ["hp_base", "hp_per_level", "mp_base", "mp_per_level", "atk_base", "atk_rand", "atk_per_level",
			"def_base", "def_per_level", "def_cap_level", "def_per_level_after"]:
		h.set(k, int(s[k]))
	h.exp_table = PackedInt32Array(s.exp_table)
	h.exp_step_after_table = int(s.exp_step_after_table)
	h.level_max = int(s.level_max)
	var r: Dictionary = d.rage
	h.rage_max = r.max
	h.rage_hit_gain = r.hit_gain_mul
	h.rage_decay_interval = _sec(r.decay_frames)
	h.rage_drain_interval = _sec(r.drain_frames)
	h.rage_freeze = r.transform_freeze_ms / 1000.0
	h.lock_hits = d.anti_lock.hits
	h.lock_window = d.anti_lock.window_ms / 1000.0
	h.lock_invincible = _sec(d.anti_lock.invincible_frames)
	var c: Dictionary = d.combo
	h.combo_cooldowns = PackedFloat32Array(c.cooldowns.map(_sec))
	h.air_cooldown = _sec(c.air_cooldown)
	h.combo_reset = m.combo_reset_ms / 1000.0
	h.cancel_progress = c.cancel_progress
	for name in d.attacks:
		var a: Dictionary = d.attacks[name].duplicate()
		a.merge(d.skills.get(name, {}))
		h.attacks[StringName(name)] = _attack(a)
	for name in d.skills:   # skills that only exist as a skill entry (hit10 itself)
		if not h.attacks.has(StringName(name)):
			var ad := _attack(d.skills[name])
			var sk: Dictionary = d.skills[name]
			if name == "hit10":
				ad.extra = {"seek_radius": float(sk.seek_radius), "seek_cooldown": _sec(sk.seek_cooldown),
					"flush_invincible": _sec(sk.flush_invincible), "slam_cooldown": _sec(sk.slam_cooldown),
					"slam_scale": float(sk.slam_scale), "rage_slam_scale": float(sk.rage_slam_scale)}
			h.attacks[StringName(name)] = ad
	h.treasures = _units(d.treasures)
	var l: Dictionary = d.learn
	h.learn_active = PackedStringArray(l.active)
	h.learn_active_cost = PackedInt32Array(l.active_cost)
	h.learn_passive = PackedStringArray(l.passive)
	h.passive_max = l.passive_max
	h.passive_cost_per_level = l.passive_cost_per_level
	for k in l.passive_bonus:
		if not k.begins_with("_"):
			h.passive_bonus[k] = Vector2(l.passive_bonus[k][0], l.passive_bonus[k][1])
	_save(h, OUT + "/%s.tres" % rig)

func _bake_monsters(d: Dictionary, auto: Dictionary) -> void:
	var c: Dictionary = d.common
	_fps = _rig_fps("wukong")
	var dr: Dictionary = c.drops
	var t := DropTable.new()
	t.potion_roll = dr.potion_chance
	t.hp_potion_chance = dr.big_or_small_hp
	t.big_hp_chance = dr.big_hp
	t.mp_potion_chance = dr.mp
	t.red_orbs = Vector2i(dr.red_orbs[0], dr.red_orbs[1])
	t.orb_count_rolls = dr.orb_counts
	t.orb_delay = _sec(dr.orb_delay_frames)
	t.orb_rise = Vector2(dr.orb_rise_px[0], dr.orb_rise_px[1])
	t.orb_rise_time = dr.orb_rise_ms / 1000.0
	t.orb_speed = Vector2(_pps(dr.orb_speed[0]), _pps(dr.orb_speed[1]))
	t.orb_accel = _pps(_pps(dr.orb_accel))
	t.orb_max_speed = _pps(dr.orb_max_speed)
	t.orb_pickup = dr.orb_pickup_px
	t.orb_life = _sec(dr.orb_life_frames)
	t.orb_hp_ratio = dr.green_hp_ratio
	t.orb_mp_ratio = dr.blue_mp_ratio
	t.orb_min_restore = dr.orb_min_restore
	t.white_rage = dr.white_rage
	t.small_hp = dr.small_hp
	t.big_hp = dr.big_hp_amount
	t.small_mp = dr.small_mp
	t.potion_life = _sec(dr.potion_life_frames)
	_save(t, OUT + "/drops.tres")

	# monster_<id>.tres from the constructor numbers, monster_<id>_<scene>.tres where a scene changes them
	var ov: Dictionary = d.get("overrides", {})
	for id in auto.monsters:
		var a: Dictionary = auto.monsters[id]
		if a.base.has("error"):
			push_warning("monster %s: %s" % [id, a.base.error])
			continue
		var rig := "monster%s" % id
		if not FileAccess.file_exists(ProjectSettings.globalize_path("res://assets/rigs/%s/rig.json" % rig)):
			continue   # art not exported yet
		_fps = _rig_fps(rig)
		var o: Dictionary = ov.get(id, {})
		# "outside": overrides for the constructor's default branch only (scenes without their own numbers)
		var base := _merged(_merged(a.base, o, rig), o.get("outside", {}), rig)
		_save(_monster(int(id), base, c), OUT + "/monsters/monster_%s.tres" % id)
		for sc in a.per_scene:
			_save(_monster(int(id), _merged(a.per_scene[sc], o, rig), c), OUT + "/monsters/monster_%s_%s.tres" % [id, sc])

## Constructor numbers + hand overrides (attacks merged per key; constructor "power" is a flat value).
func _merged(base: Dictionary, o: Dictionary, rig: String) -> Dictionary:
	var m := base.duplicate(true)
	m.rig = rig
	for an in m.attacks:
		var at: Dictionary = m.attacks[an]
		if at.has("power"):
			at.flat = at.power if at.power != null else 0
			at.erase("power")
		elif not at.has("flat"):
			at.flat = 0
	for k in o:
		if k == "outside" or k.begins_with("_"):
			continue
		if k == "attacks":
			for an in o.attacks:
				var at: Dictionary = m.attacks.get(an, {})
				at.merge(o.attacks[an], true)
				m.attacks[an] = at
		else:
			m[k] = o[k]
	return m

func _monster(id: int, m: Dictionary, c: Dictionary) -> MonsterData:
	var md := MonsterData.new()
	md.id = id
	md.display_name = m.get("name", "")
	md.rig = m.rig
	md.is_boss = m.get("boss", false)
	md.speed = _pps(_num(m.get("speed"), 3))
	md.hp = int(_num(m.get("hp"), 1000))
	md.def = int(_num(m.get("def"), 0))
	md.mdef = _num(m.get("mdef"), 0)
	md.exp = int(_num(m.get("exp"), 0))
	md.souls = int(_num(m.get("rage"), 0))
	md.sight = _num(m.get("sight"), 300)
	md.attack_range = _num(m.get("range"), 80)
	md.attack_chance = int(_num(m.get("attack_chance"), 50))
	# monsters with their own think rate (Monster32) attack on every check
	if m.has("think_frames"):
		md.attack_check = _sec(m.think_frames)
		md.attack_chance = 100
	else:
		md.attack_check = _sec(c.attack_check_frames)
	md.think_walk_at = _sec(c.think_walk_frame)
	md.walk_times = PackedFloat32Array(c.walk_frames.map(_sec))
	md.turn_pause = _sec(c.turn_pause_frames)
	md.wander_rest = _sec(c.wander_rest_frames)
	md.knockback_decay = pow(c.knockback_decay_per_frame, _fps)
	md.gravity = _pps(_pps(c.gravity))
	md.hp_bar_time = _sec(c.hp_bar_show_frames)
	md.hp_bar_fade = _sec(c.fade_out_frames)
	md.move_while_attacking = PackedStringArray(m.get("move_while_attacking", []))
	md.equip_chance = _num(m.get("equip_chance"), c.drops.equip_chance) * float(c.drops.get("equip_chance_mul", 1.0))
	md.equip_drops = PackedStringArray(m.get("equip_drops", []))
	md.stone_rate = float(m.get("stone_rate", 0.0))
	for an in m.attacks:
		md.attacks[StringName(an)] = _attack(m.attacks[an])
	md.brain_type = m.get("brain_type", "")
	md.brain = _units(m.get("brain", {}))
	md.immovable = m.get("immovable", false)
	md.behind = m.get("behind", false)
	md.is_prop = m.get("is_prop", false)
	return md

## Brain parameters: "<name>_frames" -> seconds, "<name>_pxf" -> px/s, "<name>_pxf2" -> px/s^2,
## "<name>_pxf3" -> px/s^3 (key without suffix).
func _units(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		var v = d[k]
		if v is Dictionary:
			out[k] = _units(v)
			continue
		if v is Array and not v.is_empty() and v[0] is Dictionary:
			out[k] = v.map(func(x): return _units(x) if x is Dictionary else x)
			continue
		var conv := Callable()
		var key := k
		for suf in [["_frames", _sec], ["_pxf3", func(x): return _pps(_pps(_pps(x)))],
				["_pxf2", func(x): return _pps(_pps(x))], ["_pxf", _pps]]:
			if k.ends_with(suf[0]):
				key = k.trim_suffix(suf[0])
				conv = suf[1]
				break
		out[key] = _deep(v, conv) if conv.is_valid() else v
	return out

## Apply a unit conversion to a number or to every number of (nested) arrays.
func _deep(v, conv: Callable):
	if v is Array:
		return v.map(func(x): return _deep(x, conv))
	return conv.call(v)

func _num(v, fallback: float) -> float:
	return float(v) if v != null else fallback

func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	print("baked ", path) if err == OK else push_error("save failed %s (%d)" % [path, err])
