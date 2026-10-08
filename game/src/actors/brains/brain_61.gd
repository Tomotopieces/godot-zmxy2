extends "res://src/actors/brains/boss_b.gd"
## Monster61 楚江王 (8-1 boss), template B. Far: hit3 summons a leech (Monster62, at most 5), otherwise swings;
## near: hit2 ground bursts in two rows across the arena (warning marks, then eruptions), else hit1.
## Dying with leeches alive: the leeches sacrifice themselves and he revives at full HP where one of them was.

const MARK := "monster61bullet1pre"
const BURST := "monster61bullet1"

var children: Array[Monster] = []
var _reviving := false

func far_skill(action: StringName) -> void:
	children = children.filter(func(c): return is_instance_valid(c) and c.state != Monster.State.DEAD)
	if children.size() < int(param("max_children", 5)):
		act(action)
	else:
		attack()

func can_be_hit() -> bool:
	return not _reviving

func intercept_death() -> bool:
	children = children.filter(func(c): return is_instance_valid(c) and c.state != Monster.State.DEAD)
	if children.is_empty():
		return false
	_reviving = true
	m.end_attack()
	m.state = Monster.State.ATTACK
	m.rig.visible = false
	m.velocity = Vector2.ZERO
	for c in children:
		(c.brain as Object).call("go_reburn", m)
	return true

## Called by a leech at the end of its sacrifice.
func revive_at(pos: Vector2) -> void:
	if not _reviving:
		return
	_reviving = false
	m.global_position = pos
	m.rig.visible = true
	m.hp = m.max_hp
	m.state = Monster.State.MOVE
	Level.current.boss_spawned.emit(m)

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit3":
			var c := m.summon(62, m.global_position)
			if c:
				children.append(c)
		"do_hit2":
			_bursts(param("row1_x", [1050, 1250, 1450, 1650, 1850]))
			var row2: Array = param("row2_x", [900, 1100, 1300, 1500, 1700])
			m.get_tree().create_timer(float(param("row2_delay", 2.5)), false).timeout.connect(func():
				if is_instance_valid(m) and m.state != Monster.State.DEAD:
					_bursts(row2))
		_:
			return false
	return true

func _bursts(xs: Array) -> void:
	var y := float(param("burst_y", 500))
	for x in xs:
		var pos := Vector2(x, y)
		var mark := Fx.spawn(MARK, pos)
		mark.tree_exiting.connect(func():
			if is_instance_valid(m):
				m.shoot(BURST, &"hit2").global_position = pos, CONNECT_DEFERRED)
