class_name HeroTangseng
extends Hero
## 唐僧 (Role2). No melee box: every attack is a bullet or an effect.
##   J  光弹 (hit1); hold J through its first frames to charge a piercing 蓄力弹 (hit2, 20 MP)
##   U  冰柱 (hit3)   I  分身 (swap places when it exists)   O  群体回血 (hit5)   L  落柱 (hit4, a second L drops it)

const NO_AFTERIMAGE := [&"hit4", &"hit5"]

var _shadow: TangShadow
var _charging := false
var _charge_t := 0.0
var _bar: ChargeBar
var _dropped := false   ## hit4: the pillar has been called down

func _init() -> void:
	hit_sound = "BeattackByRole2"
	sounds = {}   # played by the moves themselves, when their effect appears

func _ready() -> void:
	super()
	_bar = ChargeBar.new()
	_bar.position = Vector2(-ChargeBar.SIZE.x / 2.0, -45.0 - 30.0)
	add_child(_bar)

# ------------------------------------------------------------------ input

func _press(k: StringName, _up: bool) -> bool:
	match k:
		&"attack":
			return _normal_attack()
		&"skill_u":
			return _cast_ice()
		&"skill_i":
			return _cast_shadow()
		&"skill_o":
			return _cast_cure()
		&"skill_l":
			return _cast_fall()
	return false

## (唐僧's skills do not repeat while held.)
func _read_attack_input() -> void:
	pass

## One bullet; no chain, the input lock is the only limit (also in the air).
func _normal_attack() -> bool:
	if state != State.MOVE or cooldown > 0.0:
		return false
	cooldown = data.combo_cooldowns[0]
	_begin(&"hit1")
	return true

func _ready_to_cast(skill: StringName, action: StringName) -> bool:
	var a: AttackData = data.attacks.get(action)
	return state == State.MOVE and GameState.has_skill(skill) and a != null and mp >= a.mp_cost

func _hover(action: StringName) -> void:
	_begin(action)
	_no_gravity = true
	velocity = Vector2.ZERO

# ------------------------------------------------------------------ skills

func _cast_ice() -> bool:
	if not _ready_to_cast(&"hit3", &"hit3"):
		return false
	mp -= data.attacks[&"hit3"].mp_cost
	_hover(&"hit3")
	if is_instance_valid(_shadow):
		_shadow.do_hit3()
		_shadow = null
	return true

func _cast_shadow() -> bool:
	if state != State.MOVE or not GameState.has_skill(&"shadow"):
		return false
	if is_instance_valid(_shadow):
		Snd.sfx_varied("Role2_hit6", Hero.SKILL_PITCH)
		global_position = _shadow.global_position
		reset_physics_interpolation()
		_shadow.queue_free()
		_shadow = null
		return true
	var cost: int = data.attacks[&"shadow"].mp_cost
	if mp < cost:
		return false
	mp -= cost
	Snd.sfx_varied("Role2_hit6", Hero.SKILL_PITCH)
	_shadow = TangShadow.create(self)
	world.add_object(_shadow)
	return true

func _cast_cure() -> bool:
	if not _ready_to_cast(&"hit5", &"hit5"):
		return false
	mp -= data.attacks[&"hit5"].mp_cost
	Snd.sfx_varied("Role2_hit5", Hero.SKILL_PITCH)
	_hover(&"hit5")
	cure_at(global_position + Vector2(0, -60), true)
	if is_instance_valid(_shadow):
		_shadow.do_hit5()
		_shadow = null
	return true

## The healing light at `pos`: heals the hero when its animation ends (the shadow's never crits).
func cure_at(pos: Vector2, can_crit: bool) -> void:
	var fx := Puppet.create("tangseng_cure")
	fx.position = pos
	if transformed:
		fx.scale = Vector2.ONE * float(data.kit.cure.scale_rage)
	fx.set_additive()
	world.add_object(fx)
	fx.event.connect(func(n, _a):
		if n == &"finished":
			if is_alive():
				heal(_cure_amount(can_crit))
			fx.queue_free())
	fx.play(fx.actions[0])

## Healing of the cure skill: (max MP / 8 + 8), x1.5 transformed, x2 on a crit (the shadow's heal never crits).
func _cure_amount(can_crit: bool) -> int:
	var c: Dictionary = data.kit.cure
	var v := float(GameState.max_mp()) / float(c.divisor) + float(c.add)
	if transformed:
		v *= 1.5
	if can_crit and Rng.randf() < GameState.crit():
		v *= 2.0
	return int(v)

func _cast_fall() -> bool:
	var f: Dictionary = data.kit.fall
	if state == State.ATTACK and attack_action == &"hit4":
		# the second press, while the marker ball is out: the pillar falls on it for free
		var t := puppet.time()
		if not _dropped and t >= float(f.ball_from) and t <= float(f.ball_until):
			_dropped = true
			var ball_x := float(f.ball_start_x) + float(f.ball_speed) * (t - float(f.ball_from))
			var p := _skill_projectile("hit4falldown", &"hit4_1",
				global_position + Vector2(facing * -ball_x, float(f.ball_y) - float(f.drop_height)))
			p.facing = facing
			get_tree().create_timer(float(f.sound_delay), false).timeout.connect(Snd.sfx_varied.bind("Role2_hit4", Hero.SKILL_PITCH))
			puppet.anim.seek(float(f.resume), false)
			return true
		return false
	if not is_on_floor() or not _ready_to_cast(&"hit4", &"hit4"):
		return false
	mp -= data.attacks[&"hit4"].mp_cost
	_dropped = false
	_begin(&"hit4")
	return true

# ------------------------------------------------------------------ frame events

func _on_hero_call(n: String, _args: Array) -> void:
	match n:
		"judgexq":   # hit1 frame 2: still holding J with the charge skill learned -> charge
			if attack_action == &"hit1" and GameState.has_skill(&"hit2") and mp >= int(data.kit.charge_mp) \
					and Input.is_action_pressed("attack"):
				_begin_charge.call_deferred()
		"do_hit1":
			if attack_action == &"hit1":
				_shoot(&"hit1")
		"do_hit2":
			if attack_action == &"hit2":
				_fire_charge()
		"special_attack":
			Snd.sfx_varied("Role2_hit3", Hero.SKILL_PITCH)
			_spawn_ice(global_position, null)

func _begin_charge() -> void:
	if state != State.ATTACK or attack_action != &"hit1":
		return
	start_attack(&"hit2", data.attacks[&"hit2"])
	puppet.pause()
	_charging = true
	_charge_t = 0.0

func _fire_charge() -> void:
	var full := _charge_t >= float(data.kit.charge) and mp >= int(data.kit.charge_mp)
	_charging = false
	_charge_t = 0.0
	_bar.set_value(0.0)
	if full:
		Snd.sfx_varied("Role2_hit2", Hero.SKILL_PITCH)
		mp -= int(data.kit.charge_mp)
		_shoot(&"hit2")
	else:
		_shoot(&"hit1")

func _shoot(action: StringName) -> void:
	if action == &"hit1":
		Snd.sfx_varied("Role2_hit1", Hero.SKILL_PITCH)
	var a: AttackData = data.attacks[action]
	var p := Projectile.create(a.projectile, self, a, action)
	p.position = global_position + Vector2(a.spawn_offset.x * facing, a.spawn_offset.y)
	p.puppet.scale.x = float(data.kit["bullet1" if action == &"hit1" else "bullet2"].scale_x)
	p.facing = facing
	p.velocity = Vector2(a.speed * facing, 0)
	p.distance_left = a.distance
	if action == &"hit1":
		p.on_hit = _splash.bind(a, action)
	world.add_object(p)

## 光弹 splash: the monsters near the one it hit take the same hit.
func _splash(target, a: AttackData, action: StringName) -> void:
	if not target is Actor:
		return
	var radius := float(data.kit.bullet1.splash_radius)
	for t: Actor in world.enemies_of(self):
		if t == target or not is_instance_valid(t) or not t.can_be_hit():
			continue
		if t.center().distance_to(target.center()) <= radius:
			var h := Hit.new()
			h.source = self
			h.attack = a
			h.action = action
			h.damage = outgoing_damage(a)
			h.crit = last_crit
			h.origin = target.center()
			h.direction = facing
			t.take_hit(h)

## The 冰柱 effect at `pos`: five rounds of hits (seven transformed). From the shadow it is fixed damage without crit.
func _spawn_ice(pos: Vector2, from_shadow: Node) -> void:
	var a: AttackData = data.attacks[&"hit3"]
	var k: Dictionary = data.kit.ice
	var p := Projectile.create("tangseng_bullet3", self, a, &"hit3")
	p.position = pos
	var rounds: int = int(k.rage_rounds) if transformed else int(k.rounds)
	p.new_hit_limit = rounds - 1
	if transformed:
		p.puppet.scale = Vector2(k.rage_scale[0], k.rage_scale[1])
	p.facing = facing
	if from_shadow != null:
		var mul := float(data.kit.shadow.power_mul) * (1.5 if transformed else 1.0)
		p.damage_fn = func() -> int: return roundi(GameState.attack_power() * mul)
	world.add_object(p)

# ------------------------------------------------------------------ per frame

func _physics_process(delta: float) -> void:
	_bar.scale.x = -facing
	if _charging:
		if state != State.ATTACK or attack_action != &"hit2":
			_charging = false
			_charge_t = 0.0
			_bar.set_value(0.0)
		else:
			_charge_t = minf(_charge_t + delta, float(data.kit.charge))
			_bar.set_value(_charge_t / float(data.kit.charge))
			if not Input.is_action_pressed("attack"):
				puppet.resume()
	# hit4: the marker ball is gone and no second press came: straight to the end of the move
	var f: Dictionary = data.kit.fall
	if state == State.ATTACK and attack_action == &"hit4" and not _dropped \
			and puppet.time() > float(f.ball_until) + 0.02 and puppet.time() < float(f.resume):
		puppet.anim.seek(maxf(puppet.anim.current_animation_length - 0.02, 0.0), false)
	super(delta)

func _attack_motion() -> void:
	if attack_action in [&"hit3", &"hit5"]:
		velocity = Vector2.ZERO
	elif is_on_floor():
		velocity.x = 0.0
	else:
		velocity.x = _dir * data.walk_speed * (data.rage_speed_mul if transformed else 1.0)

func _afterimage_allowed() -> bool:
	return not (state == State.ATTACK and attack_action in NO_AFTERIMAGE)
