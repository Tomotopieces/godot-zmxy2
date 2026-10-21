extends MonsterBrain
## Static totems summoned by 阎罗王 (Monster53/54/55): no movement, one effect on a cooldown.
##   summon: create the next of `cycle` (monster ids) while the screen has room
##   heal:   every monster heals `amount`
##   drain:  every hero loses `amount` (ignores defence)

var _next := 0

func setup() -> void:
	Timers.start(m, float(param("first", param("every", 1.0))), func():
		_act()
		Timers.start(m, float(param("every", 1.0)), _act, true))

func custom_animation() -> bool:
	m.puppet.play(&"wait")
	return true

func think(_delta: float) -> void:
	m.velocity.x = 0.0

func _act() -> void:
	if m.state == Monster.State.DEAD:
		return
	match String(param("effect", "")):
		"summon":
			if m.world.monsters().size() < Layers.MAX_MONSTERS:
				var cycle: Array = param("cycle", [])
				m.summon(int(cycle[_next % cycle.size()]), m.global_position)
				_next += 1
		"heal":
			for o: Monster in m.world.monsters():
				if o.state != Monster.State.DEAD:
					o.heal(int(param("amount", 50)))
		"drain":
			for h: Hero in m.world.heroes():
				h.lose_hp(int(param("amount", 20)))

func ignores_hit(_h: Hit) -> bool:
	return true

func on_destroy() -> void:
	pass
