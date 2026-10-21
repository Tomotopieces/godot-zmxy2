class_name HeroBajie
extends Hero
## 猪八戒 (Role3): melee with a three-hit chain and four heavy skills.
##   J 连击 (hit1-3)
##   U 地刺 (hit4, ground only)   I 旋转防御 (hit6)   O 冲撞 (hit5)   W+J 聚怪 (hit8)
##   L 反伤架势 (hit7-1: no hit stun, reflects damage); L again after a moment: 飞刺 (hit7-2)

const STANCE := &"hit7-1"
const STAB := &"hit7-2"
const CANCELABLE := [&"hit1", &"hit2", &"hit3", &"hit4", &"hit5"]
const STAB_ART_ANGLE := -PI / 2.0   ## the stab art points up: heading.angle() + PI / 2 turns it along a heading

func _init() -> void:
	combo_actions = [&"hit1", &"hit2", &"hit3"]
	sounds = {&"hit1": "Role3_hit1", &"hit2": "Role3_hit2", &"hit3": "Role3_hit3", &"hit4": "Role3_hit4",
		&"hit5": "Role3_hit5", &"hit6": "Role3_hit6", STANCE: "Role3_hit7-1", STAB: "Role3_hit7-2", &"hit8": "Role3_hit8"}

# ------------------------------------------------------------------ input

func _press(k: StringName, up: bool) -> bool:
	match k:
		&"attack":
			return _cast_pull() if up else _normal_attack()
		&"skill_u":
			return _cast(&"hit4", &"hit4", true)
		&"skill_i":
			return _cast(&"hit6", &"hit6")
		&"skill_o":
			return _cast(&"hit5", &"hit5")
		&"skill_l":
			return _cast_stance()
	return false

## (八戒's skills do not repeat while held.)
func _read_attack_input() -> void:
	pass

func _cancelable_actions() -> Array:
	return CANCELABLE

## A skill: learned, not attacking / hurt, enough MP. Its input lock follows (the next normal attack waits).
func _cast(skill: StringName, action: StringName, ground_only := false) -> bool:
	var a: AttackData = data.attacks.get(action)
	if state != State.MOVE or a == null or not GameState.has_skill(skill) or mp < a.mp_cost:
		return false
	if ground_only and not is_on_floor():
		return false
	mp -= a.mp_cost
	cooldown = a.cooldown
	_begin(action)
	return true

## W+J. Not learned: nothing. Learned but short of MP: an ordinary attack.
func _cast_pull() -> bool:
	if state != State.MOVE or not GameState.has_skill(&"hit8"):
		return false
	return _cast(&"hit8", &"hit8") or _normal_attack()

func _cast_stance() -> bool:
	if not GameState.has_skill(&"hit7"):
		return false
	if state == State.ATTACK and attack_action == STANCE:
		var a: AttackData = data.attacks[STAB]
		if puppet.time() > float(data.kit.reflect.recast_after) and mp >= a.mp_cost:
			mp -= a.mp_cost
			cooldown = a.cooldown
			_begin(STAB)
			return true
		return false
	return _cast(&"hit7", STANCE)

# ------------------------------------------------------------------ motion

func _attack_motion() -> void:
	if attack_action == &"hit5":
		return   # the charge's speed comes from its animation
	if is_on_floor():
		velocity.x = 0.0
	else:
		velocity.x = _dir * data.walk_speed * (data.rage_speed_mul if transformed else 1.0)

# ------------------------------------------------------------------ taking hits

func _in_stance() -> bool:
	return state == State.ATTACK and attack_action == STANCE

func _super_armor() -> bool:
	return _in_stance()

## 旋转防御: a physical blow from something facing us does 1 (it still stuns and knocks back).
func _adjust_incoming(h: Hit, dmg: int) -> int:
	if state == State.ATTACK and attack_action == &"hit6" and h.attack.kind == AttackData.Kind.PHYSICS \
			and h.source is Actor and (h.source as Actor).facing != facing:
		return 1
	return dmg

## 反伤架势: the attacker takes twice its own attack, ignoring defense, with no knockback.
func _after_damage(h: Hit, _dmg: int) -> void:
	if _in_stance() and is_instance_valid(h.source) and h.source is Monster:
		(h.source as Monster).hurt_directly(int(h.damage * float(data.kit.reflect.mul)))

func _count_lock() -> void:
	if not _in_stance():
		super()

# ------------------------------------------------------------------ dealing damage

func outgoing_damage(a: AttackData) -> int:
	var dmg := super(a)
	if a == data.attacks.get(STAB):
		dmg += int(hp * float(data.kit.stab.hp_ratio))   # the stab also costs life: 3 % of the current HP, unmultiplied
	return dmg

## 三生锤 / 九齿钉耙: a physical hit (or the spin) may stun.
func _on_landed(target) -> void:
	if not target is Monster or attack == null:
		return
	var weapon: Item = GameState.worn[&"weapon"]
	var k: Dictionary = data.kit.stun
	if weapon == null or not weapon.id in k.items:
		return
	if attack.kind != AttackData.Kind.PHYSICS and attack_action != &"hit6":
		return
	if Rng.randf() < GameState.bonus("deephit"):
		(target as Monster).stun(float(k.duration))

# ------------------------------------------------------------------ frame events

func _on_hero_call(n: String, _args: Array) -> void:
	match n:
		"set_your_father":   # hit5: invincible while charging
			invincible = maxf(invincible, float(data.kit.hit5.invincible))
		"do_hit8":
			_pull_monsters()
		"create_stab":
			_create_stabs()

## 碎石破: every segment sounds again.
func _on_new_hit() -> void:
	if attack_action == &"hit4":
		Snd.sfx("Role3_hit4", Hero.SKILL_PITCH)

## 聚怪: every monster is dragged to just above the hero over a second.
func _pull_monsters() -> void:
	var k: Dictionary = data.kit.pull
	var skip: Array = k.exclude.map(func(x): return int(x))
	var to := global_position + Vector2(0, float(k.offset_y))
	for m: Monster in world.monsters():
		if m.data.id in skip or m.state == Monster.State.DEAD:
			continue
		var tw := m.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(m, "global_position", to, float(k.move)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 飞刺: a ring of stabs around the hero (twice as many transformed); each swings round to the last monster's position,
## then flies at it, faster and faster.
func _create_stabs() -> void:
	var k: Dictionary = data.kit.stab
	var n: int = int(k.rage_count) if transformed else int(k.count)
	var aim = null
	var all := world.monsters().filter(func(m: Monster): return m.can_be_hit())
	if not all.is_empty():
		aim = (all[-1] as Monster).global_position
	var a: AttackData = data.attacks[STAB]
	for i in n:
		var ang := TAU * float(i) / float(n)
		var start := global_position + Vector2(sin(ang), -cos(ang)) * float(k.radius)
		var s := Projectile.create("bajie_stab", self, a, STAB)
		s.position = start
		s.life = float(k.turn) + float(k.life)
		s.puppet.rotation = ang
		s.modulate.a = 0.0
		world.add_object(s)
		var heading := Vector2.DOWN
		if aim != null:
			heading = (aim - start).normalized()
			var tw := s.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
			tw.tween_property(s, "modulate:a", 1.0, float(k.turn))
			tw.tween_property(s.puppet, "rotation", heading.angle() - STAB_ART_ANGLE, float(k.turn)).from(ang)
		else:
			var tw := s.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()   # no target: turn to point down
			tw.tween_property(s, "modulate:a", 1.0, float(k.turn))
			tw.tween_property(s.puppet, "rotation", PI, float(k.turn)).from(ang)
		var turn := float(k.turn)
		s.mover = func(p: Projectile, delta: float) -> void:
			if p.age < turn:
				return
			if aim == null:
				p.velocity.y += float(k.fall) * delta
				p.position += p.velocity * delta
			else:
				# accelerates without limit (the original adds more speed every frame than the one before)
				var t := maxf(p.age - turn - float(k.quad_delay), 0.0)
				p.position += heading * (float(k.speed) + float(k.quad) * t * t) * delta
			if absf(p.position.y) > 1000.0:
				p.queue_free()
