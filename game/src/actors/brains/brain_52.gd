extends MonsterBrain
## Monster52 秦广王傀儡 (1-3 boss): never moves; swaps between five heads (wait1..wait5, each with its own
## hurt box) at random intervals and lets its puppet Monster35 fight. Killing it removes the puppet.
## A hit hides the body (its 1-frame "hurt" pose has no hurt box) until the next swap shows a new head.

const HEADS := [&"wait1", &"wait2", &"wait3", &"wait4", &"wait5"]

var _head: StringName = &"wait1"
var _swap := 0.0
var _puppet: Monster

func setup() -> void:
	m.fly = true
	m.velocity = Vector2.ZERO
	var pos: Array = param("position", [])
	if pos.size() == 2:
		m.global_position = Vector2(pos[0], pos[1])
	_swap = float(param("first_swap", 3.0))
	m.rig.play(_head)

func ignores_hit(_h: Hit) -> bool:
	return true

func on_hit(_h: Hit, _dmg: int) -> void:
	_head = &"hurt"

func custom_animation() -> bool:
	return true

func think(delta: float) -> void:
	if _puppet == null:
		_puppet = m.summon(35, m.global_position)
	m.velocity = Vector2.ZERO
	if m.state != Monster.State.MOVE:
		return
	_swap -= delta
	if _swap <= 0.0:
		var span: Array = param("swap", [2.0, 5.0])
		_swap = randf_range(span[0], span[1])
		_head = HEADS[randi() % HEADS.size()]
	m.rig.play(_head)

func on_destroy() -> void:
	if is_instance_valid(_puppet) and _puppet.state != Monster.State.DEAD:
		_puppet._vanish()
	super()
