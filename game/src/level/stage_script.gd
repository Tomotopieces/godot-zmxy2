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

## A puppet placed in the world as scenery.
func place_puppet(puppet_name: String, pos: Vector2, z := Layers.Z_MECHANISM) -> Puppet:
	var r := Puppet.create(puppet_name)
	r.position = pos
	r.z_index = z
	level.add_object(r)
	r.play(r.actions[0])
	return r
