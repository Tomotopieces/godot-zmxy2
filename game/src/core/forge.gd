class_name Forge
extends RefCounted
## Rules of the 炼丹炉 (strengthening, fusion), magic treasure growth and the shop, on plain item dictionaries.
## Numbers come from the equipment catalogue (tools/data/equipment.json -> rules).

const ELEMENT_NAMES := {"jin": "金", "mu": "木", "shui": "水", "huo": "火", "tu": "土"}

static func _cat() -> EquipmentCatalog:
	return EquipmentCatalog.get_catalog()

# ------------------------------------------------------------------ strengthening

static func can_strengthen(item: Item) -> bool:
	var d := GameState.item_data(item)
	return d != null and String(d.type) in _cat().strengthen.types

## Chance one stone adds for this equipment at its current level.
static func stone_chance(stone: Item, equip: Item) -> float:
	var d := GameState.item_data(stone)
	var row: Array = _cat().strengthen.chance.get(str(d.stone if d else 0), [])
	var plus := equip.plus
	return float(row[plus]) if plus < row.size() else 0.0

static func success_chance(equip: Item, stones: Array, luck: bool) -> float:
	var p := 0.0
	for s in stones:
		p = minf(p + stone_chance(s, equip), 1.0)
	if luck:
		p = minf(p * float(_cat().strengthen.luck_mul), 1.0)
	return p

## One attempt (the stones and charms are used up by the caller). Returns true on success.
static func strengthen(equip: Item, stones: Array, luck: bool, keep: bool) -> bool:
	var plus := equip.plus
	if Rng.randf() < success_chance(equip, stones, luck):
		equip.plus = plus + 1
		return true
	if plus >= int(_cat().strengthen.drop_from) and not keep:
		equip.plus = plus - 1
	return false

# ------------------------------------------------------------------ fusion

## Recipe made by these three materials (any order), {} when none.
static func recipe_for(mats: Array) -> Dictionary:
	if mats.size() != 3:
		return {}
	var ids: Array = mats.map(func(m: Item): return m.id)
	ids.sort()
	for r in _cat().fusion.recipes:
		var want: Array = (r.mats as Array).duplicate()
		want.sort()
		if want == ids:
			return r
	return {}

static func fusion_cost(recipe: Dictionary) -> int:
	return 0 if recipe.get("kind", "") == "stone" else int(_cat().fusion.cost)

static func fusion_chance(recipe: Dictionary) -> float:
	return float(_cat().fusion.stone_chance) if recipe.get("kind", "") == "stone" else 1.0

## Stat of an item including its strengthening.
static func _total(item: Item, stat: String) -> float:
	var d := GameState.item_data(item)
	return float(item.stats.get(stat, 0.0)) + item.plus * float(d.strengthen.get(stat, 0.0) if d else 0.0)

## The product of a recipe from its materials (null when the roll fails). Does not touch the bag or the souls.
static func produce(recipe: Dictionary, mats: Array) -> Item:
	if Rng.randf() >= fusion_chance(recipe):
		return null
	var out := EquipmentCatalog.find(recipe.out).roll()
	match recipe.kind:
		"sum":
			# the materials' own (freshly rolled) stats added up
			var s := {}
			for m in mats:
				var fresh := GameState.make_item(m.id)
				for k in ["hp", "mp", "atk", "def", "crit", "miss", "hp_regen", "mp_regen", "mdef"]:
					var v := float(fresh.stats.get(k, 0.0))
					if v != 0.0:
						s[k] = float(s.get(k, 0.0)) + v
			out.stats = s
		"average", "treasure":
			var tdef: Dictionary = _cat().treasures.defs.get(recipe.out, {})
			if tdef.has("fixed"):
				for k in tdef.fixed:
					out.stats[k] = float(tdef.fixed[k])
			else:
				for k in ["hp", "mp", "atk", "def"]:
					var sum := 0.0
					for m in mats:
						sum += float(int(_total(m, k)))
					out.stats[k] = float(int(sum / 3.0))
			if recipe.kind == "treasure":
				_init_treasure(out, tdef)
	return out

## A bare treasure as the console / tests hand out (no materials): level 1, rolled growth and elements, a 五毒兽 with its
## fixed stats; the others start with no stats (a fused one carries its materials' average).
static func new_treasure(id: String) -> Item:
	var out := EquipmentCatalog.find(id).roll()
	var tdef: Dictionary = _cat().treasures.defs.get(id, {})
	for k in tdef.get("fixed", {}):
		out.stats[k] = float(tdef.fixed[k])
	_init_treasure(out, tdef)
	return out

## A new 法宝: level 1, random growth rate (one decimal) and elements; 五毒兽 also rolls a passive and its spell.
static func _init_treasure(item: Item, tdef: Dictionary) -> void:
	var t: Dictionary = _cat().treasures
	item.lv = 1
	var g: Array = tdef.growth
	item.growth = snappedf(Rng.randf_range(g[0], g[1]), 0.1)
	# the original picks with round(rand * 4): the first and last elements are half as likely
	var names: Array = t.elements
	var first := roundi(Rng.randf() * (names.size() - 1))
	var elems := [names[first]]
	if Rng.randf() < float(t.double_chance):
		var rest: Array = names.duplicate()
		rest.remove_at(first)
		elems.append(rest[roundi(Rng.randf() * (rest.size() - 1))])
	item.elem = elems
	if tdef.has("passives"):
		var p: Array = tdef.passives[Rng.randi() % tdef.passives.size()]
		item.stats[p[0]] = float(p[1]) + float(p[2]) * roundi(Rng.randf() * float(p[3]))
		item.spell = Rng.randi() % 2
		item.strong = false

# ------------------------------------------------------------------ treasures

static func is_treasure(item: Item) -> bool:
	return item.is_treasure()

static func element_text(item: Item) -> String:
	return " ".join(item.elem.map(func(e): return ELEMENT_NAMES.get(e, e)))

static func has_element(item: Item, e: String) -> bool:
	return e in item.elem

## Souls to go from the current level to the next (0 at the top level).
static func upgrade_cost(item: Item) -> int:
	var t: Dictionary = _cat().treasures
	var lv := item.lv
	return 0 if lv >= int(t.max_level) else lv * lv * int(t.cost_mul)

## MP one use of the treasure's skill costs.
static func skill_cost(item: Item) -> int:
	var t: Dictionary = _cat().treasures
	return int(t.mp_base) + int(t.mp_per_level) * item.lv

## Level up (the caller pays): each stat grows by floor(up x growth), plus the full value for its element.
static func upgrade(item: Item) -> void:
	var t: Dictionary = _cat().treasures
	var up: Dictionary = t.defs[item.id].up
	item.lv += 1
	for e in t.element_stat:
		var stat: String = t.element_stat[e]
		var add := floorf(float(up[stat]) * item.growth)
		if has_element(item, e):
			add += float(up[stat])
		item.stats[stat] = float(item.stats.get(stat, 0.0)) + add

# ------------------------------------------------------------------ shop

static func price(id: String) -> int:
	return int(_cat().shop.prices.get(id, 0))

## Buy n of an item with 功勋. Returns the notice to show.
static func buy(id: String, n: int) -> String:
	var cost := price(id) * n
	if cost <= 0:
		return ""
	if GameState.merit < cost:
		return "功勋不足"
	var item := GameState.make_item(id)
	if not GameState.item_data(item).stacks() and n > 1:
		n = 1
		cost = price(id)
	item.n = n
	if not GameState.add_to_bag(item):
		return "背包已满"
	GameState.merit -= cost
	GameState.profile_changed.emit()
	return "购买成功"

## 功勋 for killing the rewarded boss, a limited number of times per day. Returns the amount given.
static func reward_merit(monster_id: int) -> int:
	var m: Dictionary = _cat().shop.merit
	if monster_id != int(m.monster):
		return 0
	var today := Time.get_date_string_from_system()
	if GameState.merit_day != today:
		GameState.merit_day = today
		GameState.merit_times = 0
	if GameState.merit_times >= int(m.per_day):
		return 0
	GameState.merit_times += 1
	GameState.merit += int(m.amount)
	GameState.profile_changed.emit()
	return int(m.amount)
