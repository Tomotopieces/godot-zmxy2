extends MonsterBrain
## Monster60 转轮王 form 3 (4-1 final boss): an immobile orb turret. Phase 0 throws orbs one by one to random free
## floor slots (they stay and hurt); with all slots filled, phase 1 recalls them in two waves (a pattern of four,
## then the rest) and starts over. Killing it ends the game (ending comic).

const ORB := "monster60bullet1"
const SLOTS_X := [70, 185, 300, 415, 530, 645, 760, 875]
const PATTERNS := [[0, 1, 2, 3], [4, 5, 6, 7], [0, 2, 4, 6], [1, 3, 5, 7]]

var _orbs: Array = []          ## slot -> Projectile or null
var _launched: Array[int] = [] ## slot indices in launch order
var _phase := 0
var _recall_wave := 0
var _t := 0.0
var _pattern: Array

func setup() -> void:
	m.fly = true
	m.velocity = Vector2.ZERO
	_orbs.resize(SLOTS_X.size())
	_pattern = PATTERNS[Rng.randi() % PATTERNS.size()]
	_t = float(param("first_throw", 4.0))
	m.world.start_final_platforms()

func custom_animation() -> bool:
	m.rig.play(&"wait")
	return true

func think(delta: float) -> void:
	m.velocity = Vector2.ZERO
	if m.state == Monster.State.DEAD:
		return
	_t -= delta
	if _t > 0.0:
		return
	if _phase == 0:
		_throw()
		var r: Array = param("throw_every", [2.0, 5.0])
		_t = Rng.randf_range(r[0], r[1])
		if _launched.size() >= SLOTS_X.size():
			_phase = 1
			_recall_wave = 0
			_t = float(param("recall_every", 4.0))
	else:
		var wave: Array = []
		if _recall_wave == 0:
			for i in _pattern:
				if i < _launched.size():
					wave.append(_launched[i])
		else:
			for s in _launched:
				if _orbs[s] != null:
					wave.append(s)
		for s in wave:
			_recall(s)
		_recall_wave += 1
		_t = float(param("recall_every", 4.0))
		if _recall_wave >= 2:
			_phase = 0
			_launched.clear()

func _throw() -> void:
	var free: Array[int] = []
	for i in SLOTS_X.size():
		if _orbs[i] == null:
			free.append(i)
	if free.is_empty():
		return
	var slot: int = free[Rng.randi() % free.size()]
	var o := m.shoot(ORB, &"hit1")
	o.global_position = m.center()
	var target := Vector2(m.world.view_rect().position.x + SLOTS_X[slot], float(param("slot_y", 460)))
	o.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS) \
		.tween_property(o, "global_position", target, float(param("throw_time", 2.0))) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)   # TweenMax.to eases out by default
	_orbs[slot] = o
	_launched.append(slot)

func _recall(slot: int) -> void:
	var o: Projectile = _orbs[slot]
	_orbs[slot] = null
	if not is_instance_valid(o):
		return
	var tw := o.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(o, "global_position", m.center(), float(param("recall_time", 1.0))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(o.queue_free)

func on_call(n: String, _args: Array) -> bool:
	return n == "get_round_num"

func ignores_hit(_h: Hit) -> bool:
	return true

func on_destroy() -> void:
	for o in _orbs:
		if is_instance_valid(o):
			o.queue_free()
	m.world.final_victory()
