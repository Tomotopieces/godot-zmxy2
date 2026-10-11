class_name Item
extends RefCounted
## One item of the profile (bag, worn slot, forge slot): a rolled copy of an EquipmentData. An empty slot is null.
## Saves stay JSON: to_dict() / from_dict() are the only conversion points and from_dict() validates.

var id := ""
var stats := {}            ## stat name -> rolled value
var plus := 0              ## strengthening level
var n := 1                 ## stack size (道具 page)
var lv := 0                ## magic treasure level (0 = not a treasure)
var growth := 0.0          ## treasure growth rate
var elem: Array = []       ## treasure five-element ids
var spell := 0             ## 五毒兽: which of its two spells
var strong := false        ## 五毒兽: skill strengthened with a 五毒丹

func _init(item_id := "") -> void:
	id = item_id

func data() -> EquipmentData:
	return EquipmentCatalog.find(id)

func is_treasure() -> bool:
	return lv > 0

## Id of a slot content that may be empty.
static func id_of(item: Item) -> String:
	return item.id if item else ""

func copy() -> Item:
	var c := Item.new(id)
	c.stats = stats.duplicate()
	c.plus = plus
	c.n = n
	c.lv = lv
	c.growth = growth
	c.elem = elem.duplicate()
	c.spell = spell
	c.strong = strong
	return c

func to_dict() -> Dictionary:
	var d := {"id": id, "stats": stats}
	if plus != 0: d["plus"] = plus
	if n != 1: d["n"] = n
	if lv != 0:
		d["lv"] = lv
		d["growth"] = growth
		d["elem"] = elem
		d["spell"] = spell
		d["strong"] = strong
	return d

static func _num(v: Variant) -> bool:
	return v is float or v is int

## null when `d` is not a valid item (unknown id, wrong types); numbers are clamped to sane ranges.
static func from_dict(d: Variant) -> Item:
	if not d is Dictionary or not d.get("id") is String or EquipmentCatalog.find(d.id) == null:
		return null
	var it := Item.new(d.id)
	if d.get("stats") is Dictionary:
		for k in d.stats:
			if _num(d.stats[k]):
				it.stats[str(k)] = float(d.stats[k])
	if _num(d.get("plus")): it.plus = clampi(int(d.plus), 0, 99)
	if _num(d.get("n")): it.n = clampi(int(d.n), 1, 9999)
	if _num(d.get("lv")): it.lv = clampi(int(d.lv), 0, 999)
	if _num(d.get("growth")): it.growth = float(d.growth)
	if _num(d.get("spell")): it.spell = clampi(int(d.spell), 0, 1)
	if d.get("strong") is bool: it.strong = d.strong
	if d.get("elem") is Array:
		it.elem = (d.elem as Array).filter(func(e): return e is String)
	return it
