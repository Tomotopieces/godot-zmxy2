extends MonsterBrain
## Distance-band template ("template D", 05_monsters.md §1): no hurt guard (keeps deciding while hurt),
## never chases; picks by horizontal distance to the target:
##   <= near_band: skill3 when ready, else every check tick 70 % hit1 / 30 % wander
##   <= mid_band:  skill2 when ready (80 % roll per tick), else the same 70/30
##   <= far_band:  skill1 when ready (cooldown far_cd + rand * far_cd_rand)
##   farther:      wander
## Params: skill1/skill2/skill3 (actions), near_band, mid_band, far_band (px), cd1, cd2, cd3, far_cd_rand, check.

var _check := 0.0

func think(delta: float) -> void:
	if m.state == Monster.State.DEAD or m.is_attacking():
		return
	if m.target == null:
		wander(delta)
		select_target()
		return
	if not m.is_on_floor() and not m.fly:
		return
	var dx := absf(m.to_target().x)
	if dx <= float(param("near_band", 150)):
		if _try_skill("skill3", "cd3", 1.0):
			return
		_melee_or_walk(delta)
	elif dx <= float(param("mid_band", 300)):
		if _try_skill("skill2", "cd2", 0.8):
			return
		_melee_or_walk(delta)
	elif dx <= float(param("far_band", 800)):
		if not _try_skill("skill1", "cd1", 1.0, float(param("far_cd_rand", 0.0))):
			wander(delta)
	else:
		wander(delta)

func _try_skill(skill: String, cd_key: String, chance: float, rand_extra := 0.0) -> bool:
	var action: String = param(skill, "")
	if action == "" or m.cd(cd_key) > 0.0 or Rng.randf() >= chance:
		return false
	m.set_cd(cd_key, float(param(cd_key, 4.0)) + Rng.randf() * rand_extra)
	m.face_target()
	use_skill(StringName(action))
	return true

func _melee_or_walk(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return   # stands its ground between checks (the original only walks on the 30 % branch of a check)
	_check = float(param("check", 1.0))
	if Rng.randf() < 0.7:
		attack()
	else:
		wander(delta)

func use_skill(action: StringName) -> void:
	act(action)

## Template D bosses do get interrupted: BaseMonster.beAttack puts any monster that is hit into "hurt" (only the short
## setYourFather windows at the start of a skill protect it); what the template lacks is the hurt guard of the AI,
## so it decides on its next move straight away.
