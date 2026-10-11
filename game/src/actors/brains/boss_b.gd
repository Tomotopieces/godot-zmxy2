extends MonsterBrain
## Shared boss template ("template B", 05_monsters.md §1):
## far from the target -> skill1 when its cooldown is ready, else chase;
## close -> on every check tick, skill2 when ready, else hit1 (no chance roll).
## Params: far_skill / near_skill (action names, "" = none), far_cd / near_cd (s), check (s),
## range_y_mul (vertical reach in attack ranges, default 2), face_far (face target before skill1).

var _check := 0.0     ## free-running check clock (the original's `count % 24`: it keeps counting through attacks)

func think(delta: float) -> void:
	_check -= delta
	var tick := _check <= 0.0
	if tick:
		_check += float(param("check", 1.0))
	if m.state != Monster.State.MOVE:
		return
	if m.target == null:
		wander(delta)
		select_target()
		return
	if not m.is_on_floor() and not m.fly:
		return
	var d := m.to_target()
	if absf(d.y) > m.data.attack_range * float(param("range_y_mul", 2.0)):
		wander(delta)
		return
	if absf(d.x) > m.data.attack_range:
		var far: String = param("far_skill", "")
		if far != "" and m.cd("far") <= 0.0:
			m.face_target()
			m.set_cd("far", float(param("far_cd", 3.0)))
			far_skill(StringName(far))
		else:
			follow()
		return
	m.dir = 0
	if not tick:
		return
	var near: String = param("near_skill", "")
	if near != "" and m.cd("near") <= 0.0:
		m.set_cd("near", float(param("near_cd", 4.0)))
		m.face_target()
		near_skill(StringName(near))
	else:
		attack()

## Override for skills that do more than play an action.
func far_skill(action: StringName) -> void:
	act(action)

func near_skill(action: StringName) -> void:
	act(action)
