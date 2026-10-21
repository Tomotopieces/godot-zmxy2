@tool
class_name MonsterSpawn
extends Marker2D
## Where a stop's monsters appear (MonsterAppearPoint), a child of its CameraStop: after `delay` s one monster every
## `interval` s until `total`, while fewer than Layers.MAX_MONSTERS are alive. `boss` makes it a boss (HP bar).

@export var monster := 30   ## data/monsters/monster_<id>.tres (or monster_<id>_<stage>.tres)
@export var delay := 2.0
@export var interval := 1.0
@export var total := 1
@export var boss := false

var spawned := 0
var data: MonsterData
var _t := 0.0

func finished() -> bool:
	return spawned >= total

func tick(delta: float, level: Level) -> void:
	if finished():
		return
	_t += delta
	if _t < delay + interval * spawned or level.monsters().size() >= Layers.MAX_MONSTERS:
		return
	var d := data
	if d.id == 79:   # MainGame.createMonster: 劈天斧 79 or, half the time, 风神盾 80 (30000 HP)
		d = level.monster_data(79 + Rng.randi() % 2)
	var m := Monster.create(d)
	m.position = global_position
	level.add_monster(m)
	spawned += 1
