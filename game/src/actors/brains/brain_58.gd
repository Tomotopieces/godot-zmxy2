extends "res://src/actors/brains/boss_d.gd"
## Monster58 刑天 (7-1 boss), distance bands. Far: hit2-1 leap; mid: hit3 pull (every hero dragged to him); close:
## hit4. The leap ends in a hover above the arena (invulnerable, drifting toward a hero) until he slams down
## (hit2-2, marked by a shadow). On death the exit opens briefly, then closes and 战神刑天 (81) appears.

var _hovering := false
var _fall := 0.0
var _first_fall := true

func think(delta: float) -> void:
	if _hovering:
		_hover(delta)
		return
	super(delta)

func _hover(delta: float) -> void:
	m.velocity.y = 0.0
	var h: Hero = m.world.hero
	if h:
		m.velocity.x = signf(h.global_position.x - m.global_position.x) * float(param("hover_speed", 120))
	_fall -= delta
	if _fall <= 0.0:
		_hovering = false
		m.rig.visible = true   # he comes into view as he drops
		m.fly = false
		# untouchable through the whole drop, up to the end of the flames on the floor (a hit would cancel them)
		m.invuln = m.rig.anim.get_animation(&"hit2-2").length
		# the shadow lies on the floor, under the monsters and the hero (the original adds it just below him in the draw order)
		Fx.spawn("monster58shallow", Vector2(m.global_position.x, float(param("shadow_y", 510)))).z_index = Layers.Z_MONSTER - 1
		act(&"hit2-2")

func moves_while_attacking() -> bool:
	return _hovering

func on_call(n: String, _args: Array) -> bool:
	match n:
		"in_top":
			_hovering = true
			m.rig.visible = false   # up in the sky he is out of sight (the original left his soles showing at the top)
			m.fly = true
			m.invuln = 9999.0
			if _first_fall:
				_first_fall = false
				_fall = float(param("first_fall", 2.0))
			else:
				var r: Array = param("fall", [2.0, 4.0])
				_fall = Rng.randf_range(r[0], r[1])
		"do_hit3":
			pull_heroes(float(param("pull_time", 0.6)))
		_:
			return false
	return true

func on_action_finished(action: StringName) -> void:
	if action == &"hit2-1" and _hovering:
		m.state = Monster.State.ATTACK   # stays up until the slam
		m.rig.play(&"wait")

func on_destroy() -> void:
	m.world.open_door()
	var t := m.get_tree().create_timer(float(param("next_delay", 5.0)), false)
	var lv := m.world
	var pos: Array = param("next_pos", [500, 300])
	t.timeout.connect(func():
		if is_instance_valid(lv):
			lv.close_door()
			var md := lv.monster_data(81)
			if md:
				var nx := Monster.create(md)
				nx.position = Vector2(pos[0], pos[1])
				lv.add_monster(nx))
