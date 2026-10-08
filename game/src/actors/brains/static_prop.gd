extends MonsterBrain
## Things that never act: loot objects (Monster65/66, guaranteed drop when broken) and similar props.
## Never moves, never attacks; plays wait.

func custom_animation() -> bool:
	m.rig.play(&"wait")
	return true

func think(_delta: float) -> void:
	m.velocity.x = 0.0

func ignores_hit(_h: Hit) -> bool:
	return true
