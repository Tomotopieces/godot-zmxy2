class_name HeroDebuffs
extends Node
## Status effects put on the hero by monsters (deadlink, net, magiclost, eyefix, poison ...): time left per effect and the
## effect icons that follow the hero. A child node of Hero, ticked by the hero.

const ICONS := {
	&"deadlink": ["fx_deadlink", Vector2(0, -40)], &"magiclost": ["fx_magiclost", Vector2.ZERO],
	&"eyefix": ["fx_eyefix", Vector2(0, -20)], &"poison": ["fx_poison", Vector2(0, -70)],
}

var _left := {}    ## name -> seconds left
var _icons := {}   ## name -> Rig

func add(n: StringName, seconds: float) -> void:
	_left[n] = maxf(_left.get(n, 0.0), seconds)

func clear(n: StringName = &"") -> void:
	if n == &"":
		_left.clear()
	else:
		_left.erase(n)

func has(n: StringName) -> bool:
	return _left.has(n)

func tick(delta: float) -> void:
	for k in _left.keys():
		_left[k] -= delta
		if _left[k] <= 0.0:
			_left.erase(k)
	for k in ICONS:
		var on: bool = _left.has(k)
		if on and not _icons.has(k):
			var r := Rig.create(ICONS[k][0])
			r.position = ICONS[k][1]
			get_parent().add_child(r)
			r.play(r.actions[0])
			r.action_finished.connect(func(a): r.play(a, true))
			_icons[k] = r
		elif not on and _icons.has(k):
			_icons[k].queue_free()
			_icons.erase(k)
