class_name StageScript
extends Node
## Special rules of one stage (the original StageListenerXY). Lives at src/level/stages/<level name>.gd,
## is added as a child of its Level and gets the stage's numbers from data/stages.json as `p`.

var level: Level
var p: Dictionary

func setup() -> void:
	pass

## Up was pressed (enter doors). Return true to consume it.
func on_up(_hero: Hero) -> bool:
	return false

func on_monster_added(_m: Monster) -> void:
	pass

func param(key: String, fallback = 0.0):
	return p.get(key, fallback)

static var _all := {}

## Numbers shared by several stages (top-level keys of data/stages.json).
static func shared(key: String) -> Dictionary:
	if _all.is_empty():
		_all = JSON.parse_string(FileAccess.get_file_as_string("res://data/stages.json"))
	return _all.get(key, {})

## The 刑天门 of stages 2-2 / 2-3 / 11-1.
func add_xingtian_door() -> void:
	var d: Node = load("res://src/level/stages/xingtian_door.gd").new()
	d.set("stage", self)
	d.set("cfg", shared("xingtian_door"))
	add_child(d)

## Scene object of a kind exported in level.json "doors" (white-bone door, fires...).
func features(kind: String) -> Array:
	return level.features.filter(func(f): return f.kind == kind)

## Hero touching an area of the world.
const HERO_BOUNDS_MARGIN := 3.0

func hero_in(r: Rect2) -> bool:
	var h := level.hero
	# the original tests the hero's whole display bounds, a few px larger than its hurt box
	return is_instance_valid(h) and h.is_alive() and r.intersects(h.hurt_rect().grow(HERO_BOUNDS_MARGIN))

## The hero's current attack hitbox touches `r` (stick test of the original doors / pearls).
func hero_hits(r: Rect2) -> bool:
	var h := level.hero
	if not is_instance_valid(h) or h.attack == null:
		return false
	var hr := h.rig.hit_rect()
	return hr.size != Vector2.ZERO and hr.intersects(r)

## A rig placed in the world as scenery.
func place_rig(rig_name: String, pos: Vector2, z := Layers.Z_MECHANISM) -> Rig:
	var r := Rig.create(rig_name)
	r.position = pos
	r.z_index = z
	level.add_object(r)
	r.play(r.actions[0])
	return r
