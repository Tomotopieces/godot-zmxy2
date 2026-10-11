class_name EquipmentData
extends Resource
## One equipment / item definition (my/AllEquipment.as). Stats roll between min and max when it drops.

const STATS := [&"hp", &"mp", &"atk", &"def", &"crit", &"miss", &"hp_regen", &"mp_regen", &"lifesteal", &"mdef", &"deephit"]
const SLOTS := [&"weapon", &"cloth", &"accessory", &"treasure", &"fashion", &"wing"]   ## types the hero can wear

@export var id := &""
@export var display_name := ""
@export var type := &""          ## weapon / cloth / accessory / item / fashion / wing / treasure
@export var user := ""           ## required character ("" = anyone)
@export var show := 1            ## appearance variant on the rig
@export var quality := ""
@export var value := 0           ## sell price in souls
@export var color := Color.WHITE
@export var stats := {}          ## stat -> Vector2(min, max)
@export var strengthen := {}     ## stat -> bonus per strengthening level
@export var stone := 0           ## strengthening stone level (0 = not a stone)
@export var charm := &""         ## luck / keep (strengthening charms)
@export_multiline var desc := ""
@export var icon: Texture2D
@export var ground_icon: Texture2D


## Items (道具) stack in the bag.
func stacks() -> bool:
	return type == &"item"

func wearable_by(character: String) -> bool:
	return type in SLOTS and (user == "" or user == character)

## A dropped copy with rolled stats.
func roll() -> Item:
	var s := {}
	for k in stats:
		var r: Vector2 = stats[k]
		# whole numbers, or whole percents for the fractional stats; every value of the range equally likely
		var whole := r.x == roundf(r.x) and r.y == roundf(r.y)
		s[String(k)] = Rng.stepped(r.x, r.y, 1.0 if whole else 0.01)
	var it := Item.new(String(id))
	it.stats = s
	return it
