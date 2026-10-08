extends Node
## Persistent player profile (survives level changes): level, exp, souls, skills, bag and worn equipment.
## Live HP/MP/rage belong to the Hero node; this only stores what carries between stages.
##
## Items are Item objects (rolled copies of an EquipmentData); they save as JSON through Item.to_dict().
## Optional keys: "n" stack size (道具), "plus" strengthening level.

signal profile_changed
signal leveled_up(level: int)
signal equipment_changed
signal buffs_changed

const SLOTS := 6
const HERO_DATA := "res://data/wukong.tres"
const CHARACTER := "悟空"

var hero_data: HeroData
var level := 1
var exp := 0
var souls := 0
var attack := 0          ## rolled once per level (original: 10 + rand(0..4) + 5(L-1))
var skills := {}                     ## learned active skills (action -> true), bought in the skill shop
var passives := [0, 0, 0, 0, 0]      ## passive skill levels (hp, mp, crit, hp_regen, mp_regen)
var bag: Array[Item] = []                                        ## carried items
var worn := {&"weapon": null, &"cloth": null, &"accessory": null, &"treasure": null, &"fashion": null, &"wing": null}   ## slot -> Item (null = empty)
var buffs := {}                      ## timed buff -> seconds of stage time left (used items)
var merit := 0                       ## 功勋: shop currency
var merit_day := ""                  ## date of the last 功勋 reward (it is limited per day)
var merit_times := 0                 ## rewards taken on merit_day
var stage := Vector2i(1, 1)          ## stage being played (or last played)
var progress := Vector2i(1, 1)       ## furthest unlocked stage-level on the main path (1-1 .. 4-1)
var opening_seen := false            ## opening comic shown
var hhe_seen := false                ## 红孩儿 comic shown (first visit to 6-1)
var slot := -1                       ## save slot of this game (-1 = never saved)

func _ready() -> void:
	if not ResourceLoader.exists(HERO_DATA):
		return   # running a bake tool before data exists
	hero_data = load(HERO_DATA)
	new_game()

# ------------------------------------------------------------------ stats

## Sum of a stat over worn items and passive skills.
func bonus(stat: String) -> float:
	var t := 0.0
	for k in worn:
		var it: Item = worn[k]
		if it == null:
			continue
		t += float(it.stats.get(stat, 0.0))
		if it.plus > 0:
			t += it.plus * float(item_data(it).strengthen.get(stat, 0.0))
	var i := hero_data.learn_passive.find(stat)
	if i >= 0:
		t += hero_data.passive_value(stat, passives[i])
	return t

# ------------------------------------------------------------------ skill shop

func learn_cost(i: int) -> int:
	return hero_data.learn_active_cost[i]

func learn(i: int) -> bool:
	var s := StringName(hero_data.learn_active[i])
	if skills.get(s, false) or souls < learn_cost(i):
		return false
	souls -= learn_cost(i)
	skills[s] = true
	profile_changed.emit()
	return true

func passive_cost(i: int) -> int:
	return (passives[i] + 1) * hero_data.passive_cost_per_level

func upgrade_passive(i: int) -> bool:
	if passives[i] >= hero_data.passive_max or souls < passive_cost(i):
		return false
	souls -= passive_cost(i)
	passives[i] += 1
	equipment_changed.emit()   # max HP / MP may change
	profile_changed.emit()
	return true

func max_hp() -> int:
	return int((hero_data.max_hp(level) + int(bonus("hp"))) * buff_value("hp_mul", 1.0))

func max_mp() -> int:
	return hero_data.max_mp(level) + int(bonus("mp"))

func attack_power() -> int:
	return attack + int(bonus("atk"))

func defense() -> int:
	return hero_data.defense(level) + int(bonus("def"))

func crit() -> float:
	return bonus("crit")

func miss() -> float:
	return bonus("miss")

func hp_regen() -> int:
	return int(bonus("hp_regen"))

func mp_regen() -> int:
	return int(bonus("mp_regen") + buff_value("mp_regen", 0.0))

## Equipment / stone drop rate multiplier: 双倍爆率 buff and the worn fashion.
func drop_mul() -> float:
	var cat := EquipmentCatalog.get_catalog()
	return buff_value("drop_mul", 1.0) * (1.0 + float(cat.drop_bonus.get(Item.id_of(worn[&"fashion"]), 0.0)))

func exp_to_next() -> int:
	return hero_data.exp_to_next(level)

func has_skill(s: StringName) -> bool:
	return skills.get(s, false)

## Rig appearance ids of the worn gear (1 = bare).
func appearance() -> Dictionary:
	var out := {"cloth": 1, "weapon": 1, "wing": 1}
	for slot in [&"cloth", &"weapon", &"wing"]:
		var d := item_data(worn[slot])
		if d:
			out[String(slot)] = d.show
	# a fashion replaces the look of the clothes (User.getEquipNum)
	var f := item_data(worn[&"fashion"])
	if f and f.show > 1:
		out["cloth"] = f.show
	return out

# ------------------------------------------------------------------ buffs

## Value of an effect of the running buffs (first buff that has it).
func buff_value(key: String, fallback: float) -> float:
	var defs: Dictionary = EquipmentCatalog.get_catalog().buffs
	for b in buffs:
		if defs.get(b, {}).has(key):
			return float(defs[b][key])
	return fallback

## Buff timers only run during a stage (HeroBuff.step).
func tick_buffs(delta: float) -> void:
	for b in buffs.keys():
		buffs[b] -= delta
		if buffs[b] <= 0.0:
			buffs.erase(b)
			equipment_changed.emit()
			buffs_changed.emit()

## Using it again restarts the timer; it does not stack.
func add_buff(b: String) -> void:
	buffs[b] = EquipmentCatalog.get_catalog().buff_time
	equipment_changed.emit()
	buffs_changed.emit()

func usable(item: Item) -> bool:
	return EquipmentCatalog.get_catalog().use.has(item.id)

## Use bag[index] (道具 page). Returns the notice to show.
func use_item(index: int) -> String:
	var u: Dictionary = EquipmentCatalog.get_catalog().use.get(bag[index].id, {})
	if u.is_empty():
		return ""
	if u.has("special"):
		var refused := _use_special(u.special)
		if refused != "":
			return refused
	else:
		add_buff(u.buff)
	var d := item_data(bag[index])
	_remove_one(index)
	profile_changed.emit()
	return "使用 %s" % d.display_name

## 五毒丹: permanently strengthens the worn 五毒兽's active skill. Returns the refusal notice, "" when used.
func _use_special(kind: String) -> String:
	if kind == "wds_power":
		var t: Item = worn[&"treasure"]
		if Item.id_of(t) != "wds":
			return "您没有装备五毒兽"
		if t.strong:
			return "五毒兽技能已经强化"
		t.strong = true
	return ""

## One revive from the worn 苍生挂饰; the charm is used up.
func consume_revive() -> bool:
	if Item.id_of(worn[&"accessory"]) != EquipmentCatalog.get_catalog().revive.get("item", "-"):
		return false
	worn[&"accessory"] = null
	equipment_changed.emit()
	profile_changed.emit()
	return true

# ------------------------------------------------------------------ progression

## Exp beyond a level carries over (the original dropped it), possibly through several levels at once;
## the top level gains no more exp.
func add_exp(amount: int) -> void:
	if level >= hero_data.level_max:
		return
	exp += amount
	while level < hero_data.level_max and exp >= exp_to_next():
		exp -= exp_to_next()
		level += 1
		attack = hero_data.attack_power(level)
		leveled_up.emit(level)
	if level >= hero_data.level_max:
		exp = 0
	profile_changed.emit()

func add_souls(amount: int) -> void:
	souls += amount
	profile_changed.emit()

# ------------------------------------------------------------------ items

func item_data(item: Item) -> EquipmentData:
	return EquipmentCatalog.find(item.id) if item else null

func tab_of(item: Item) -> String:
	var d := item_data(item)
	return EquipmentCatalog.get_catalog().tab_of(d.type) if d else "equip"

## Bag indices shown on a page, in bag order.
func tab_items(tab: String) -> Array:
	var out: Array = []
	for i in bag.size():
		if tab_of(bag[i]) == tab:
			out.append(i)
	return out

## Each bag page holds bag_size entries.
func tab_full(tab: String) -> bool:
	return tab_items(tab).size() >= EquipmentCatalog.get_catalog().bag_size

func count_of(id: String) -> int:
	var n := 0
	for it in bag:
		if it.id == id:
			n += it.n
	return n

func is_worn(id: String) -> bool:
	for k in worn:
		if Item.id_of(worn[k]) == id:
			return true
	return false

## Whether the item would fit (page not full, or it stacks on an existing entry; unique items only once).
func can_add(item: Item) -> bool:
	var d := item_data(item)
	if d == null:
		return false
	var id := item.id
	if id in EquipmentCatalog.get_catalog().unique and (has_item(id) or is_worn(id)):
		return false
	return (d.stacks() and has_item(id)) or not tab_full(tab_of(item))

## force: no capacity check (items coming back from a forge slot).
func add_to_bag(item: Item, force := false) -> bool:
	if not force and not can_add(item):
		return false
	var d := item_data(item)
	if d.stacks():
		for it in bag:
			if it.id == item.id:
				it.n += item.n
				profile_changed.emit()
				return true
	bag.append(item)
	profile_changed.emit()
	return true

## A fresh copy of a catalogue item (rolled stats).
func make_item(id: String) -> Item:
	var d := EquipmentCatalog.find(id)
	if d == null:
		return null
	return Forge.new_treasure(id) if d.type == &"treasure" else d.roll()

## Take one out of bag[index] (a single copy when it is a stack).
func take_at(index: int) -> Item:
	var one := bag[index].copy()
	one.n = 1
	_remove_one(index)
	profile_changed.emit()
	return one

## Take one off the stack at bag[index].
func _remove_one(index: int) -> void:
	if bag[index].n > 1:
		bag[index].n -= 1
	else:
		bag.remove_at(index)

## Throw away the whole entry (道具 page 丢弃).
func discard(index: int) -> void:
	bag.remove_at(index)
	profile_changed.emit()

func can_wear(item: Item) -> bool:
	var d := item_data(item)
	return d != null and d.wearable_by(CHARACTER)

## Wear bag[index]; whatever was in that slot goes back to the bag.
func wear(index: int) -> bool:
	var item := bag[index]
	if not can_wear(item):
		return false
	var slot := item_data(item).type
	bag.remove_at(index)
	if worn[slot] != null:
		bag.insert(index, worn[slot])
	worn[slot] = item
	equipment_changed.emit()
	profile_changed.emit()
	return true

func take_off(slot: StringName) -> bool:
	if worn[slot] == null or tab_full(tab_of(worn[slot])):
		return false
	bag.append(worn[slot])
	worn[slot] = null
	equipment_changed.emit()
	profile_changed.emit()
	return true

func has_item(id: String) -> bool:
	return bag.any(func(it: Item): return it.id == id)

## Use up one item from the bag (keys of hidden stages). Returns false when there is none.
func take_item(id: String) -> bool:
	for i in bag.size():
		if bag[i].id == id:
			_remove_one(i)
			profile_changed.emit()
			return true
	return false

## Sell bag[index] for souls.
func sell(index: int) -> bool:
	var d := item_data(bag[index])
	if d == null:
		return false
	bag.remove_at(index)
	souls += d.value
	profile_changed.emit()
	return true

# ------------------------------------------------------------------ progress

## Main path: 1-1 .. 3-3 then 4-1 (MainGame.__levelClear). Only clearing the frontier advances it;
## hidden stages (5..11) never do.
const MAIN_PATH_LAST := Vector2i(4, 1)

func is_unlocked(s: Vector2i) -> bool:
	return s.x < progress.x or (s.x == progress.x and s.y <= progress.y)

func on_stage_cleared(s: Vector2i) -> void:
	if s != progress or s.x > 3:
		return
	progress = Vector2i(s.x + 1, 1) if s.y == 3 else Vector2i(s.x, s.y + 1)

## Next stage on the main path after s (stages 1..3 have three levels).
static func next_stage(s: Vector2i) -> Vector2i:
	return Vector2i(s.x + 1, 1) if s.y >= 3 else Vector2i(s.x, s.y + 1)

# ------------------------------------------------------------------ save slots (SaveGame)

func _to_dict() -> Dictionary:
	return SaveGame.to_dict(self)

func save_to(i: int) -> bool:
	if not SaveGame.write(i, SaveGame.to_dict(self)):
		return false
	slot = i
	return true

## Autosave after a level clear (only once the game has a slot).
func autosave() -> bool:
	return slot >= 0 and save_to(slot)

func slot_info(i: int) -> Dictionary:
	return SaveGame.info(i)

func load_from(i: int) -> bool:
	var d := SaveGame.read(i)
	if d.is_empty():
		return false
	new_game()
	slot = i
	SaveGame.apply(self, d)
	equipment_changed.emit()
	profile_changed.emit()
	return true

func new_game() -> void:
	level = 1
	exp = 0
	souls = 0
	attack = hero_data.attack_power(level)
	skills.clear()
	passives = [0, 0, 0, 0, 0]
	bag.clear()
	for k in worn:
		worn[k] = null
	stage = Vector2i(1, 1)
	progress = Vector2i(1, 1)
	opening_seen = false
	hhe_seen = false
	buffs.clear()
	merit = 0
	merit_day = ""
	merit_times = 0
	slot = -1
	equipment_changed.emit()
	profile_changed.emit()
