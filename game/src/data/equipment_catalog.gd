class_name EquipmentCatalog
extends Resource
## All equipment definitions, baked from tools/data/equipment.json.

const PATH := "res://data/equipment.tres"

@export var items: Dictionary = {}     ## id -> EquipmentData
@export var regen_interval := 1.0      ## seconds between hp/mp regen ticks
@export var bag_size := 25
@export var ground_life := 10.0        ## seconds a dropped item stays (boss loot stays)
@export var boss_loot: PackedStringArray
@export var buff_time := 3600.0        ## seconds of stage time a used buff item lasts
@export var use := {}                  ## usable item id -> {buff} / {special}
@export var buffs := {}                ## buff name -> {effects: *_add / *_mul / mp_regen, icon, icon_scale}
@export var kill_buffs := {}           ## monster id (as text) -> buff its death grants (国庆: 劈天斧 / 风神盾)
@export var kill_merit := {}            ## monster id (as text) -> {stage, merit, text}: 功勋 for killing it in that stage (七夕)
@export var moon := {}                 ## 中秋: {cake, big, big_cost, weapon_cost, weapons: {hero -> weapon id}}
@export var drop_bonus := {}           ## fashion id -> extra drop rate
@export var stone_drop := {}           ## {item, level_caps: {level name -> max hero level, -1 = always}}
@export var tabs := {}                 ## bag page -> item types (each page holds bag_size entries)
@export var unique: PackedStringArray  ## items the hero can only own one of
@export var strengthen := {}           ## {types, chance: {stone level -> [chance at +0..]}, luck_mul, drop_from}
@export var fusion := {}               ## {cost, stone_chance, recipes: [{out, mats, kind}]}
@export var treasures := {}            ## {max_level, cost_mul, mp_base, mp_per_level, elements, defs}
@export var shop := {}                 ## {pages, prices, per_page, merit}
@export var revive := {}               ## {item, invincible, ratio, max_y}

static var _inst: EquipmentCatalog

static func get_catalog() -> EquipmentCatalog:
	if _inst == null:
		_inst = load(PATH)
	return _inst

## Bag page of an item type.
func tab_of(type: StringName) -> String:
	for t in tabs:
		if String(type) in tabs[t]:
			return t
	return "equip"

static func find(id: String) -> EquipmentData:
	return get_catalog().items.get(StringName(id))
