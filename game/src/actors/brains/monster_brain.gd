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
var _reviving := false       ## between two lives (45 reburns, 61 waits for a leech): cannot be hit, does nothing

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
	return not _reviving

func on_action_finished(_action: StringName) -> void:
	pass

func on_died() -> void:
	pass

## HP reached 0. Return true to take over (revive phases); the monster then stays alive.
func intercept_death() -> bool:
	return false

## The boss starts a revive / re-burn instead of dying: it stops where it is and cannot be hit until the brain ends it.
func begin_revive() -> void:
	_reviving = true
	m.end_attack()
	m.velocity = Vector2.ZERO

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

# ------------------------------------------------------------------ calls other brains / stage scripts make on a boss
# (declared here so they are checked by the parser instead of being looked up by name; the boss that has the move overrides)

## The leech 62 tells its master 61 that it is done: 61 comes back at `pos`.
func revive_at(_pos: Vector2) -> void:
	pass

## The master 61 tells a leech 62 to go and burn out.
func go_reburn(_master: Monster) -> void:
	pass

## The fires are lit (2-2): the 判官 fight begins.
func real_start() -> void:
	pass

## A hub stone was just hit (10-1 doors).
func recently_hit() -> bool:
	return false

# ------------------------------------------------------------------ pieces shared by the boss templates

var _clock := 0.0

## The check clock of the original AI (`count % 24 == 0`): true on the one tick of every period it fires on. It runs
## freely - through attacks, hurt and every branch of the AI - so call it once per think(), before any early return.
func tick_check(delta: float, key := "check", fallback := 1.0) -> bool:
	_clock -= delta
	if _clock > 0.0:
		return false
	_clock += float(param(key, fallback))
	return true

## No target: wander and look for one. True when there is a target to act on.
func ensure_target(delta: float) -> bool:
	if m.target != null:
		return true
	wander(delta)
	select_target()
	return false

## A skill's cooldown gate: when it is ready, start the next cooldown and return true.
func cooldown_ready(key: String, seconds: float) -> bool:
	if m.cd(key) > 0.0:
		return false
	m.set_cd(key, seconds)
	return true

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
			if Rng.randi() % 100 < m.data.attack_chance:
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
		m.dir = 1 if off < -400.0 else (-1 if off > 400.0 else (1 if Rng.randf() < 0.5 else -1))
		_stop_at = m.data.walk_times[Rng.randi() % m.data.walk_times.size()]
	if _cycle >= _stop_at:
		if Rng.randf() < 0.5:
			m.dir = 0
		if _cycle >= _stop_at + Rng.randf() * m.data.wander_rest:
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
