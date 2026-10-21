extends MonsterBrain
## Monster68, 五官王's ghost turret: never walks, its attacks can't be interrupted, and it fades away after a while.

func setup() -> void:
	Timers.start(m, float(param("life", 15.0)), m.vanish)

func think(delta: float) -> void:
	super(delta)
	m.velocity.x = 0.0

func move_speed() -> float:
	return 0.0

func ignores_hit(_h: Hit) -> bool:
	return m.is_attacking()

func on_call(n: String, _args: Array) -> bool:
	if n != "do_hit1":
		return false
	m.face_target()
	m.shoot("monster68bullet1", &"hit1", Vector2(10, -30))
	return true
