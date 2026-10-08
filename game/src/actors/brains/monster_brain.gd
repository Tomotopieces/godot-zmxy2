class_name MonsterBrain
extends RefCounted
## Decision making of a monster. This base class is the plain BaseMonster AI:
## wander, spot the hero (sight / range), chase, attack on a fixed check interval with a chance roll.
## Per-monster scripts live next to this file as brain_<id>.gd or a shared template (MonsterData.brain_type);
## their tuning comes from MonsterData.brain (frames already converted to seconds by the bake).

const DIR := "res://src/actors/brains/"

var m: Monster
var p: Dictionary            ## MonsterData.brain parameters
var _cycle := 0.0
var _stop_at := 3.0
var _attack_t := 0.0
var _pause := 0.0

static var _scripts := {}   ## monster id -> brain script (or null = the base brain)

static func _script_for(data: MonsterData) -> Script:
	if not _scripts.has(data.id):
		var path := DIR + "brain_%d.gd" % data.id
		if not ResourceLoader.exists(path) and data.brain_type != "":
			path = DIR + "%s.gd" % data.brain_type
		_scripts[data.id] = load(path) if ResourceLoader.exists(path) else null
	return _scripts[data.id]

static func create(monster: Monster) -> MonsterBrain:
	var script := _script_for(monster.data)
	var b: MonsterBrain = script.new() if script else MonsterBrain.new()
	b.m = monster
	b.p = monster.data.brain
	return b

## Parameter with fallback.
func param(key: String, fallback = 0.0):
	return p.get(key, fallback)

# ------------------------------------------------------------------ hooks (override as needed)

func setup() -> void:
	pass

## Called every physics tick while alive. Default: no thinking while hurt or attacking ("hurt guard").
func think(delta: float) -> void:
	if m.state != Monster.State.MOVE:
		return
	base_ai(delta)

## Any animation event before the default handling. Return true to consume it.
func on_event(_n: StringName, _args: Array) -> bool:
	return false

## Animation call event (do_hit1, do_hit2 ...). Return true when handled.
func on_call(_name: String, _args: Array) -> bool:
	return false

func on_hit(_h: Hit, _dmg: int) -> void:
	pass

## The hit interrupted the monster (it is about to play hurt).
func on_hurt_start() -> void:
	pass

## A hero was hit by this monster's attack / projectile.
func on_hit_hero(_hero: Hero, _action: StringName) -> void:
	pass

func modify_damage(_h: Hit, dmg: int) -> int:
	return dmg

## Damage of this monster's attack (constructor "power").
func outgoing_damage(a: AttackData) -> int:
	return a.flat if a and a.flat > 0 else 1

## True: the hit does damage but no hurt state / knockback.
func ignores_hit(_h: Hit) -> bool:
	return false

func can_be_hit() -> bool:
	return true

func on_action_finished(_action: StringName) -> void:
	pass

func on_died() -> void:
	pass

## HP reached 0. Return true to take over (revive phases); the monster then stays alive.
func intercept_death() -> bool:
	return false

## Removed from the level (after the death animation). Bosses open the exit by default.
func on_destroy() -> void:
	if m.data.is_boss:
		m.world.boss_destroyed(m)

func moves_while_attacking() -> bool:
	return false

## Walking speed (px/s).
func move_speed() -> float:
	return m.data.speed

## True when the brain drives the walk / wait animation itself.
func custom_animation() -> bool:
	return false

# ------------------------------------------------------------------ base AI pieces

func base_ai(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		return
	if m.target == null:
		wander(delta)
		select_target()
		return
	if not m.is_on_floor() and not m.fly:
		return
	var d := m.to_target()
	if absf(d.y) > m.data.attack_range * 2.0:
		wander(delta)
	elif absf(d.x) > m.data.attack_range:
		follow()
	else:
		_attack_t -= delta
		if _attack_t <= 0.0:
			_attack_t = m.data.attack_check
			if randi() % 100 < m.data.attack_chance:
				attack()
			else:
				m.dir = 0

## selectTarget: the hero within sight horizontally and within attack range vertically.
func select_target() -> void:
	var h: Hero = m.world.hero
	if h and h.is_alive() and absf(h.global_position.y - m.global_position.y) <= m.data.attack_range \
			and absf(h.global_position.x - m.global_position.x) < m.data.sight:
		m.target = h

func follow() -> void:
	if m.target:
		m.dir = 1 if m.target.global_position.x > m.global_position.x else -1

## Wander cycle (normalWalk): pick a side shortly after the cycle starts, walk, then idle a while.
func wander(delta: float) -> void:
	var prev := _cycle
	_cycle += delta
	if prev < m.data.think_walk_at and _cycle >= m.data.think_walk_at:
		var off := m.global_position.x - m.world.view_rect().get_center().x
		m.dir = 1 if off < -400.0 else (-1 if off > 400.0 else (1 if randf() < 0.5 else -1))
		_stop_at = m.data.walk_times[randi() % m.data.walk_times.size()]
	if _cycle >= _stop_at:
		if randf() < 0.5:
			m.dir = 0
		if _cycle >= _stop_at + randf() * m.data.wander_rest:
			_cycle = 0.0
			m.dir = 0

## Turn around (isTurnBack markers).
func turn_back() -> void:
	m.dir = -m.dir
	_pause = m.data.turn_pause

## attackTarget: face the target and swing hit1.
func attack(action: StringName = &"hit1") -> void:
	m.face_target()
	act(action)

## Play an attack action with its invulnerable window (param "invuln_<action>", seconds).
func act(action: StringName) -> bool:
	m.invuln = maxf(m.invuln, float(param("invuln_" + String(action), 0.0)))
	return m.attack_with(action)

## Every hero is pulled to the monster over `time` (no damage).
func pull_heroes(time: float) -> void:
	for h: Hero in m.world.heroes():
		if h.is_alive():
			var tw := h.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			tw.tween_property(h, "global_position", m.global_position, time)
