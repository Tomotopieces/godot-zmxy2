class_name HubPropBrain
extends MonsterBrain
## Stage 10 hub props (Monster70 round selector, Monster71 stones): can't be killed or moved.
## 70: every hit advances its pointer (0..4). 71: remembers being hit for a short moment.
## StageListener101 (the hub script) reads `pointer` / `recently_hit()`.

var pointer := 0
var _hit_t := 0.0
var _pointer_puppet: Puppet

func setup() -> void:
	m.fly = true
	m.velocity = Vector2.ZERO
	if param("pointer", false):
		# the dial's needle: a 5-frame clip that steps on one frame per hit (pointMc.play(), every frame stop()s)
		_pointer_puppet = Puppet.create("hub_pointer")
		m.add_child(_pointer_puppet)
		_pointer_puppet.play(&"f0")

func custom_animation() -> bool:
	return true

func think(delta: float) -> void:
	m.velocity = Vector2.ZERO
	_hit_t = maxf(_hit_t - delta, 0.0)
	if m.hp < m.max_hp:
		m.hp = m.max_hp

func ignores_hit(_h: Hit) -> bool:
	return true

func on_hit(_h: Hit, _dmg: int) -> void:
	_hit_t = float(param("hit_memory", 0.5))
	if param("pointer", false):
		pointer = (pointer + 1) % 5
		_pointer_puppet.play(StringName("f%d" % pointer))
		m.invuln = float(param("hit_invuln", 1.0))
		m.world.hub_pointer_changed(m, pointer)

func recently_hit() -> bool:
	return _hit_t > 0.0

func on_destroy() -> void:
	pass
