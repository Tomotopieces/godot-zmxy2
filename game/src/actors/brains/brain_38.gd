extends MonsterBrain
## Monster38 秦广王 (2-1 boss). Chases; close: every check tick hit2 (homing bomb orbs) when ready, else hit1 (bolt).
## DEADLINK: on a timer every hero is linked for a while; damage a linked hero deals to 38 hurts that hero too.

const BOLT := "monster38bullet1"
const ORB_SPAWNER := "monster38bullet2"
const ORB := "monster38bullet2_2"
const BOMB := "monster38bullet2_3"
const EXPLODE := "bullet2explode"

var _check := 0.0
var _link := 0.0
var _orbs: Array[Projectile] = []

func setup() -> void:
	_link = float(param("link_first", 10.0))

func think(delta: float) -> void:
	# the link timer runs on every tick, even while hurt
	_link -= delta
	if _link <= 0.0:
		_link = float(param("link_every", 15.0))
		for h: Hero in Level.current.heroes():
			if h.is_alive():
				h.add_debuff(&"deadlink", float(param("link_time", 5.0)))
	if m.state != Monster.State.MOVE:
		return
	if m.target == null:
		wander(delta)
		select_target()
		return
	if not m.is_on_floor():
		return
	var d := m.to_target()
	if absf(d.y) > float(param("reach_y", 300)):
		wander(delta)
	elif absf(d.x) > m.data.attack_range:
		follow()
	else:
		m.dir = 0
		_check -= delta
		if _check <= 0.0:
			_check = float(param("check", 1.0))
			m.face_target()
			if m.cd("orbs") <= 0.0:
				m.set_cd("orbs", float(param("orb_cd", 5.25)))
				m.attack_with(&"hit2")
			else:
				m.attack_with(&"hit1")

func modify_damage(h: Hit, dmg: int) -> int:
	if h.source is Hero and (h.source as Hero).has_debuff(&"deadlink"):
		(h.source as Hero).lose_hp(dmg)
	return dmg

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit1":
			m.shoot(BOLT, &"hit1", Vector2.ZERO, Vector2(float(param("bolt_speed", 360)), 0), float(param("bolt_distance", 1500)))
		"do_hit2":
			_cast_orbs()
		_:
			return false
	return true

## doHit2: 4-7 spawner clips above the boss; each releases a homing orb when its animation ends.
## (Remake: the cap counts live orbs; the original leaked slots and stopped casting.)
func _cast_orbs() -> void:
	_orbs = _orbs.filter(func(o): return is_instance_valid(o))
	if _orbs.size() >= int(param("orb_cap", 10)):
		return
	for i in 3 + ceili(randf() * 4.0):
		var pos := m.global_position + Vector2((randf() - 0.5) * 100.0, -200.0)
		var fx := Fx.spawn(ORB_SPAWNER, pos)
		fx.tree_exiting.connect(_spawn_orb.bind(pos), CONNECT_DEFERRED)

func _spawn_orb(pos: Vector2) -> void:
	if not is_instance_valid(m) or m.state == Monster.State.DEAD:
		return
	var o := m.shoot(ORB, &"hit2-2")
	o.global_position = pos
	o.life = float(param("orb_life", 10.0))
	_orbs.append(o)
	var target := m.target
	var t_dx := float(param("orb_turn", 1.0))
	var t_dy := float(param("orb_wobble", 0.5))
	var arm := float(param("orb_arm", 2.0))
	var st := {"vx": 0.0, "vy": 0.0, "tx": t_dx, "ty": t_dy}   # lambdas capture locals by value
	o.mover = func(p: Projectile, delta: float) -> void:
		st.tx += delta
		st.ty += delta
		if is_instance_valid(target):
			if st.tx >= t_dx:
				st.tx = 0.0
				st.vx = signf(target.global_position.x - p.global_position.x) * float(param("orb_speed", 120))
			if st.ty >= t_dy:
				st.ty = 0.0
				st.vy = randf_range(-1.0, 1.0) * float(param("orb_wobble_speed", 60))
			# drop a bomb once it hovers over the target
			if p.age >= arm and absf(target.global_position.x - p.global_position.x) < float(param("orb_drop_dx", 50)):
				_drop_bomb(p.global_position)
				p.queue_free()
				return
		p.position += Vector2(st.vx, st.vy) * delta

func _drop_bomb(pos: Vector2) -> void:
	var b := m.shoot(BOMB, &"hit2-3", Vector2.ZERO, Vector2(0, float(param("bomb_speed", 240))), float(param("bomb_distance", 9999)))
	b.global_position = pos
	b.on_hit = func(target: Actor) -> void:
		Fx.spawn(EXPLODE, target.center())

func on_destroy() -> void:
	for o in _orbs:
		if is_instance_valid(o):
			o.queue_free()
	super()
