extends "res://src/actors/brains/boss_b.gd"
## Monster47 孟婆 (3-3 boss), template B. Far: hit3 bouncing orb; near: hit2 (every hero loses skills for a while)
## or hit1 bolt. Below 50 % HP it summons 悟空怪 (48), below 25 % 唐僧怪 (49); while a summon lives she stands
## still, half transparent and invulnerable.

const BOLT := "monster47bullet2"
const ORB := "monster47bullet1"

var _phase := 0
var _summon: Monster

func think(delta: float) -> void:
	if is_instance_valid(_summon) and _summon.state != Monster.State.DEAD:
		m.invuln = 9999.0
		m.dir = 0
		return
	if _summon != null:
		_summon = null
		m.modulate.a = 1.0
		m.invuln = float(param("resume_invuln", 1.0))
	super(delta)
	var r := float(m.hp) / m.max_hp
	if m.state == Monster.State.MOVE and ((_phase == 0 and r < 0.5) or (_phase == 1 and r < 0.25)):
		_summon = m.summon(48 if _phase == 0 else 49, Vector2(m.global_position.x, float(param("summon_y", 400))))
		_phase += 1
		m.modulate.a = 0.5
		m.velocity = Vector2.ZERO
		m.rig.play(&"wait")

func on_call(n: String, _args: Array) -> bool:
	match n:
		"do_hit1":
			m.shoot(BOLT, &"hit1", Vector2(40, 0), Vector2(float(param("bolt_speed", 360)), 0), float(param("bolt_distance", 1500)))
		"do_hit2":
			for h: Hero in m.world.heroes():
				if h.can_be_hit():
					h.add_debuff(&"magiclost", float(param("magiclost", 5.0)))
		"do_hit3":
			_bounce_orb()
		_:
			return false
	return true

## Bounces off the screen edges and the floor at constant speed until it hits a hero
## (the original never expires; capped here).
func _bounce_orb() -> void:
	var sp := float(param("orb_speed", 360))
	var o := m.shoot(ORB, &"hit3", Vector2(140, -180), Vector2(sp, sp))
	o.life = float(param("orb_life", 20.0))
	var floor_y := float(param("floor_y", 500))
	o.mover = func(p: Projectile, delta: float) -> void:
		var v := p.velocity
		var next := p.global_position + v * delta
		var view := Level.current.view_rect()   # (not the boss: it may be gone while its orb still flies)
		if next.x < view.position.x or next.x > view.end.x:
			v.x = -v.x
		if next.y < 0.0 or next.y > floor_y:
			v.y = -v.y
		p.velocity = v
		p.position += v * delta
