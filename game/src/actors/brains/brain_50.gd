extends MonsterBrain
## Monster50 (4-1 mob): keeps wandering while the target is in reach; within `reach_x` it attacks on the check tick
## with hit2 (front blast, cooldown) or hit1; farther away it chases.

var _check := 0.0

func think(delta: float) -> void:
	if m.state != Monster.State.MOVE:
		return
	if m.target == null:
		wander(delta)
		select_target()
		return
	if not m.is_on_floor():
		return
	var d := m.to_target()
	if absf(d.y) > float(param("reach_y", 600)):
		wander(delta)
		return
	if absf(d.x) > float(param("reach_x", 300)):
		follow()
		return
	_check -= delta
	if _check > 0.0:
		wander(delta)
		return
	_check = float(param("check", 1.0))
	m.face_target()
	if m.cd("blast") <= 0.0:
		m.set_cd("blast", float(param("blast_cd", 4.0)))
		m.attack_with(&"hit2")
	else:
		m.attack_with(&"hit1")

func on_call(n: String, _args: Array) -> bool:
	if n != "do_hit2":
		return false
	m.shoot("monster50bullet1", &"hit2", Vector2(20, 0))
	return true
