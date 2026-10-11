class_name Spawner
extends RefCounted
## Monster appear point (MonsterAppearPoint): after `delay` s, one monster every `interval` s until `total`,
## while fewer than Layers.MAX_MONSTERS are alive.

var data: MonsterData
var pos: Vector2
var delay: float
var interval: float
var total: int
var spawned := 0
var _t := 0.0

func _init(d: MonsterData, p: Vector2, dl: float, iv: float, n: int) -> void:
	data = d
	pos = p
	delay = dl
	interval = iv
	total = n

func finished() -> bool:
	return spawned >= total

func tick(delta: float, level: Level) -> void:
	if finished():
		return
	_t += delta
	var due := delay + interval * spawned
	if _t < due or level.monsters().size() >= Layers.MAX_MONSTERS:
		return
	var d := data
	if d.id == 79:   # MainGame.createMonster: 劈天斧 79 or, half the time, 风神盾 80 (30000 HP)
		d = level.monster_data(79 + Rng.randi() % 2)
	var m := Monster.create(d)
	m.position = pos
	level.add_monster(m)
	spawned += 1
