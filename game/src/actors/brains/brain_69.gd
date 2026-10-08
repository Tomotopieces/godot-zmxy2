extends MonsterBrain
## Monster69 卞城王 (10-3 boss). After taking enough knockbacks he splits (fenshen): a clone appears next to him and
## times out later. Far: hit2 volley of six shots (cooldown) or chase; near, every check tick: hit3 quake when
## ready, else hit1. Clones are plain copies (not bosses) and die with the original.

var _split_left := 20
var _check := 0.0
var _clone_life := 0.0
var clones: Array[Monster] = []

func setup() -> void:
	_split_left = int(param("split_hits", 20))
	if m.summoner != null:
		# a clone: not the boss, no exp, limited life
		m.data = m.data.duplicate()
		m.data.is_boss = false
		m.data.exp = 0
		_clone_life = float(param("clone_life", 20.0))

func think(delta: float) -> void:
	if _clone_life > 0.0:
		_clone_life -= delta
		if _clone_life <= 0.0:
			m.damage_directly(999999)
			return
	if m.is_attacking() or m.state == Monster.State.DEAD or m.is_hurt():
		return
	if _split_left <= 0:
		var r: Array = param("split_reset", [10, 20])
		_split_left = randi_range(r[0], r[1])
		act(&"fenshen")
		return
	if m.target == null:
		wander(delta)
		select_target()
		return
	var d := m.to_target()
	if absf(d.y) > float(param("reach_y", 300)):
		wander(delta)
	elif absf(d.x) > m.data.attack_range:
		if m.cd("volley") <= 0.0:
			m.set_cd("volley", float(param("volley_cd", 7.5)))
			m.face_target()
			act(&"hit2")
		else:
			follow()
	else:
		m.dir = 0
		_check -= delta
		if _check <= 0.0:
			_check = float(param("check", 1.0))
			m.face_target()
			if m.cd("quake") <= 0.0:
				m.set_cd("quake", float(param("quake_cd", 10.8)))
				act(&"hit3")
			else:
				act(&"hit1")

func on_hurt_start() -> void:
	_split_left -= 1

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_fenshen":
			if m.world.monsters().size() < int(param("max_monsters", 5)):
				var c := m.summon(69, m.global_position + Vector2(20.0 * m.facing, 0))
				if c:
					clones.append(c)
		"do_hit2":
			var b := m.shoot("monster69bullet1", &"hit2", Vector2(0, -20 + randf_range(-40, 40)))
			b.rig.scale.x = absf(b.rig.scale.x) * -m.facing
		_:
			return false
	return true

func on_destroy() -> void:
	for c in clones:
		if is_instance_valid(c):
			c.damage_directly(999999)
	super()
