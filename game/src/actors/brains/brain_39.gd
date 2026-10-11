extends MonsterBrain
## Monster39 判官 (2-2 boss).
## Intro: plays "ready" (raises his hands) and then holds the casting pose, whose nested glow clips keep looping
## (rig monster39_ready); invulnerable until the stage releases it (StageListener22 fires; real_start()).
## Every hit2 interval it casts hit2 (self speed-up buff). Sped up: runs at high speed keeping ~400 px from the
## target, hops, and attacks on its own short timer; normal: base AI with an invulnerable wind-up.
## hit1 fires three bolts (frames 10 / 31 / 52).

const BOLT := "monster39bullet1"

var _started := false
var _hit2_t := 0.0
var _speedup := 0.0
var _strike_t := 0.0
var _move_t := 0.0
var _hop_t := 0.0
var _cast: Rig

const CAST_RIG := "monster39_ready"
const CAST_OFFSET := Vector2(0.1, -3.95)   ## body position in the ready frame of Monster39

func setup() -> void:
	m.invuln = 9999.0
	m.play_action(&"ready")
	m.rig.action_finished.connect(_hold_cast, CONNECT_ONE_SHOT)
	# outside 2-2 (no fires to light) the boss starts by itself
	if not m.world.params.has("panguan"):
		m.after(float(param("intro", 6.0)), real_start)

## After "ready": the held casting pose with its looping glow.
func _hold_cast(_a: StringName) -> void:
	if _started or not is_instance_valid(m):
		return
	_cast = Rig.create(CAST_RIG)
	_cast.position = Vector2(CAST_OFFSET.x * m.rig.scale.x, CAST_OFFSET.y)
	_cast.scale = m.rig.scale
	m.add_child(_cast)
	_cast.play(_cast.actions[0])
	m.rig.visible = false

## StageListener22.realStart: the fires are lit, the fight begins.
func real_start() -> void:
	if _started or not is_instance_valid(m):
		return
	_started = true
	if is_instance_valid(_cast):
		_cast.queue_free()
	m.rig.visible = true
	m.invuln = float(param("start_invuln", 1.0))
	m.state = Monster.State.MOVE
	m.rig.play(&"wait")
	_hit2_t = float(param("hit2_first", 3.0))

func can_be_hit() -> bool:
	return _started

func think(delta: float) -> void:
	if not _started:
		return
	_speedup = maxf(_speedup - delta, 0.0)
	_hit2_t -= delta
	if _hit2_t <= 0.0 and m.state == Monster.State.MOVE:
		_hit2_t = float(param("hit2_every", 30.0))
		m.invuln = maxf(m.invuln, float(param("hit2_invuln", 1.33)))
		m.attack_with(&"hit2")
		return
	if m.state != Monster.State.MOVE:
		return
	if _speedup > 0.0 and m.target:
		_sped_up(delta)
	else:
		base_ai(delta)

func _sped_up(delta: float) -> void:
	_strike_t -= delta
	_move_t -= delta
	_hop_t -= delta
	if _strike_t <= 0.0:
		_strike_t = float(param("fast_strike", 1.0)) * ceili(Rng.randf() * 3.0)
		attack()
		return
	if _move_t <= 0.0:
		_move_t = float(param("fast_move", 4.0))
		var tx := m.target.global_position.x
		m.dir = -1 if m.global_position.x > tx - float(param("keep_away", 400)) else 1
	if _hop_t <= 0.0 and m.is_on_floor():
		_hop_t = float(param("fast_hop", 2.0))
		m.velocity.y = -float(param("hop_speed", 360))

func attack(action: StringName = &"hit1") -> void:
	m.invuln = maxf(m.invuln, float(param("hit1_invuln", 1.0)))
	super(action)

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit1":
			m.shoot(BOLT, &"hit1-1", Vector2(50, 0), Vector2(float(param("bolt_speed", 360)), 0), float(param("bolt_distance", 1500)))
		"do_hit2":
			_speedup = float(param("speedup_time", 20.0))
			_strike_t = float(param("fast_strike_first", 2.0))
		_:
			return false
	return true

## Movement speed follows the buff (horizenSpeed 20 sped up, 4 normally).
func move_speed() -> float:
	return float(param("fast_speed", 480)) if _speedup > 0.0 else m.data.speed
