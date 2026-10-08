extends MonsterBrain
## Monster78 墓碑, 平等王's tombstone: falls into place, then every tick drains HP and MP from every hero
## (ignores defence) until it is broken.

var _t := 0.0

func setup() -> void:
	m.invuln = float(param("spawn_invuln", 1.0))
	m.play_action(&"fall")
	_t = float(param("every", 1.0))

func custom_animation() -> bool:
	m.rig.play(&"wait")
	return true

func think(delta: float) -> void:
	m.velocity.x = 0.0
	if m.attack_action == &"fall":
		if m.is_on_floor():
			m.end_attack()
			m.state = Monster.State.MOVE
		return
	_t -= delta
	if _t <= 0.0:
		_t = float(param("every", 1.0))
		for h: Hero in m.world.heroes():
			if h.is_alive():
				h.lose_hp(int(param("drain_hp", 200)))
				h.mp = maxi(h.mp - int(param("drain_mp", 50)), 0)

func ignores_hit(_h: Hit) -> bool:
	return true
