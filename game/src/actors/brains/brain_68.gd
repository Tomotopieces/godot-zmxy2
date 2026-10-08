extends MonsterBrain
## Monster68, 五官王's ghost turret: never walks, its attacks can't be interrupted, and it fades away after a while.

var _life := 0.0

func setup() -> void:
	_life = float(param("life", 15.0))

func think(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		m.vanish()
		return
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
