class_name Loot
extends RefCounted
## Monster death drops (BaseMonster.dropAura / addMedicine): potions, then soul orbs for the killer.

const TABLE := "res://data/drops.tres"

static var _table: DropTable

static func table() -> DropTable:
	if _table == null:
		_table = load(TABLE)
	return _table

static func drop(m: Monster) -> void:
	var t := table()
	var pos := m.global_position
	var roll := Rng.randf()
	if Rng.randf() >= t.potion_roll:
		if roll <= t.hp_potion_chance:
			var big := roll <= t.big_hp_chance and Rng.randf() < 0.5
			Potion.spawn(Potion.Kind.BIG_HP if big else Potion.Kind.SMALL_HP, pos, t)
	elif Rng.randf() <= t.mp_potion_chance:
		Potion.spawn(Potion.Kind.SMALL_MP, pos, t)

	_drop_equipment(m)

	var hero := m.target
	if hero == null or not hero.is_alive():
		return
	for i in Rng.randi_range(t.red_orbs.x, t.red_orbs.y):
		Orb.spawn(Orb.Kind.RED, pos + _jitter(10), hero, m.data.souls, t)
	var restore_hp := maxi(t.orb_min_restore, int(hero.max_hp * t.orb_hp_ratio))
	var restore_mp := maxi(t.orb_min_restore, int(hero.max_mp * t.orb_mp_ratio))
	var kinds := [[Orb.Kind.GREEN, restore_hp, 20], [Orb.Kind.BLUE, restore_mp, 30], [Orb.Kind.WHITE, t.white_rage, 40]]
	for k in kinds:
		for i in _orb_count(t):
			Orb.spawn(k[0], pos + _jitter(k[2]), hero, k[1], t)

## Equipment: independent of the potions above and of the stone below, each with its own roll.
## One random item of the monster's drop list, pushed back on screen when it dies at the edge.
static func _drop_equipment(m: Monster) -> void:
	var mul := GameState.drop_mul()
	if not m.data.equip_drops.is_empty() and Rng.randf() <= m.data.equip_chance * mul:
		# one roll decides whether anything drops, a second picks among the monster's items with equal chance
		# (the original's round(rand * (n - 1)) made the first and last entry half as likely: a hidden weighting)
		_ground(m, m.data.equip_drops[Rng.randi() % m.data.equip_drops.size()])
	# bosses also drop a 1级强化石 while the hero is not over-levelled for the stage (BaseMonster.dropStone)
	var st: Dictionary = EquipmentCatalog.get_catalog().stone_drop
	var cap := int(st.get("level_caps", {}).get(Level.current.level_name, 0))
	if m.data.is_boss and cap != 0 and (cap < 0 or GameState.level <= cap) and Rng.randf() <= m.data.stone_rate * mul:
		_ground(m, st.item)

static func _ground(m: Monster, id: String) -> void:
	var v := Level.current.view_rect()
	var sx := m.global_position.x - v.position.x
	var push := -150.0 if sx > v.size.x - 10.0 else (150.0 if sx < 10.0 else 0.0)
	GroundItem.spawn(id, m.global_position + Vector2(push + (Rng.randf() - 0.5) * 20.0, -100.0))

static func _orb_count(t: DropTable) -> int:
	var r := Rng.randf()
	for c in t.orb_count_rolls:
		if r < c[0]:
			return int(c[1])
	return 0

static func _jitter(spread: float) -> Vector2:
	return Vector2(Rng.randf() - 0.5, Rng.randf() - 0.5) * spread
