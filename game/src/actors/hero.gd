class_name Hero
extends Actor
## Wukong: input, movement, 5-hit combo, skills (hit6-hit10), rage transform, getting hit.
## Numbers come from HeroData (baked from the original, px / seconds).

enum State { MOVE, ATTACK, HURT, DEAD }

const COMBO := [&"hit1", &"hit2", &"hit3", &"hit4", &"hit5"]
const CANCEL_INTO_HIT8 := [&"hit1", &"hit2", &"hit3", &"hit4"]
const SCRIPTED_MOTION := [&"hit6", &"hit7", &"hit10"]   ## velocity comes from animation events
const SOUNDS := {&"hit1": "Role1_hit1AndHit2", &"hit2": "Role1_hit1AndHit2", &"hit3": "Role1_hit3AndHit4",
	&"hit4": "Role1_hit3AndHit4", &"hit5": "Role1_hit5", &"hit6": "Role1_hit6", &"hit7": "Role1_hit7",
	&"hit8": "Role1_hit8", &"hit9": "Role1_hit9", &"hit10": "Role1_hit10_1"}
const DROP_THROUGH_TIME := 0.3
const FALL_DEATH_Y := 1500.0
const AFTERIMAGE_FADE := 1.0

var data: HeroData
var state := State.MOVE
var mp := 0
var max_mp := 0
var rage := 0
var transformed := false
var jump_count := 0
var running := false
var invincible := 0.0
var cooldown := 0.0          ## attack input lockout (original `timers`)
var combo_step := 0

var _clock := 0.0
var _dir := 0
var _held := {-1: false, 1: false}
var _pressed_at := {-1: -100.0, 1: -100.0}
var _last_attack_at := -100.0
var _no_gravity := false
var _no_input := false
var _hit10_down := false
var _lock_count := 0
var _last_hurt_at := -100.0
var _rage_t := 0.0
var _drop_t := 0.0
var debuffs := HeroDebuffs.new()   ## status effects set by monsters
var _poison := [0.0, 1.0, 0.0]   ## power, tick (s), elapsed
var held_by: Node = null   ## grabbed (setStatic + setLostKeyboard by a monster): no input, no own movement
var _lock_glow := 0.0   ## anti-lock protection time left (the only invincibility the original shows)
var treasure: Treasure  ## worn magic treasure following the hero (H)
var controls_locked := false   ## stage over: no more input

func _ready() -> void:
	data = GameState.hero_data
	gravity = data.gravity
	collision_layer = LAYER_HERO
	collision_mask = LAYER_WORLD | LAYER_ONEWAY
	setup_rig(data.rig)
	add_child(debuffs)
	_apply_appearance()
	facing = 1
	refill()
	invincible = data.spawn_invincible
	GameState.leveled_up.connect(_on_level_up)
	GameState.equipment_changed.connect(_on_equipment_changed)
	_sync_treasure.call_deferred()

func _apply_appearance() -> void:
	var look := GameState.appearance()
	for k in look:
		rig.set_equip(k, look[k])

## Gear changes keep the current HP / MP, clamped to the new maximums.
func _on_equipment_changed() -> void:
	_apply_appearance()
	_sync_treasure()
	max_hp = GameState.max_hp()
	max_mp = GameState.max_mp()
	hp = mini(hp, max_hp)
	mp = mini(mp, max_mp)

## The treasure companion matches the worn treasure (a new one when it changes or levels up).
func _sync_treasure() -> void:
	var it: Item = GameState.worn[&"treasure"]
	if is_instance_valid(treasure) and treasure.item == it and it != null:
		return
	if is_instance_valid(treasure):
		treasure.queue_free()
	treasure = null
	if it != null and is_inside_tree() and world:
		treasure = Treasure.create(self, it)
		world.add_object(treasure)

func refill() -> void:
	max_hp = GameState.max_hp()
	max_mp = GameState.max_mp()
	hp = max_hp
	mp = max_mp

func _on_level_up(_level: int) -> void:
	refill()
	Fx.attach("fx_levelup", self, rig.markers.get("levelupmc", Vector2.ZERO))

func can_be_hit() -> bool:
	return state != State.DEAD and invincible <= 0.0

func _physics_process(delta: float) -> void:
	_clock += delta
	dealer.tick(delta)
	cooldown = maxf(cooldown - delta, 0.0)
	invincible = maxf(invincible - delta, 0.0)
	_update_rage(delta)
	_update_regen(delta)
	debuffs.tick(delta)
	if has_debuff(&"magiclost"):
		_drain_mp_by_moving()
	if has_debuff(&"poison"):
		_poison[2] += delta
		if _poison[2] >= _poison[1]:
			_poison[2] = 0.0
			lose_hp(int(_poison[0]))
	if _drop_t > 0.0:
		_drop_t -= delta
		if _drop_t <= 0.0:
			collision_mask |= LAYER_ONEWAY
	if held_by != null and not is_instance_valid(held_by):
		held_by = null
	if state != State.DEAD and not input_locked():
		if not _no_input:
			_read_input()
		_update_velocity()
	elif input_locked():
		# grabbed / netted / petrified (setStatic): rooted and standing, not sliding or walking on
		velocity.x = 0.0
		_dir = 0
		running = false
	if not _no_gravity:
		apply_gravity(delta)
	move_and_slide()
	_after_move()
	_clamp_to_view()
	if state == State.ATTACK:
		scan_hits(world.enemies_of(self))
	_update_tint(delta)
	if global_position.y > FALL_DEATH_Y and state != State.DEAD:
		hp = 0
		_die()

# ------------------------------------------------------------------ input

func _read_input() -> void:
	for d in [-1, 1]:
		var act := "move_left" if d < 0 else "move_right"
		if Input.is_action_just_pressed(act):
			# double tap: two presses of the same direction within the window (a long press never counts)
			if _clock - _pressed_at[d] < data.double_tap_window:
				running = true
				_pressed_at[d] = -100.0
			else:
				_pressed_at[d] = _clock
		if Input.is_action_just_released(act):
			running = false
	var l := Input.is_action_pressed("move_left")
	var r := Input.is_action_pressed("move_right")
	# the most recently pressed direction wins (executeLastDirKey)
	if Input.is_action_just_pressed("move_left"):
		_dir = -1
	elif Input.is_action_just_pressed("move_right"):
		_dir = 1
	elif not (l and r):
		_dir = -1 if l else (1 if r else 0)
	if _dir == 0:
		running = false
	elif Input.is_action_pressed("run"):   # gamepad: hold LB to run
		running = true

	if Input.is_action_just_pressed("jump"):
		if Input.is_action_pressed("move_down"):
			_try_drop_through()
		else:
			_try_jump()
	if Input.is_action_just_pressed("attack"):
		# up+attack: nothing until 升龙斩 is learned (Role1 "0101"); without MP it falls back to a normal hit
		if Input.is_action_pressed("move_up"):
			if GameState.has_skill(&"hit8") and not _try_skill(&"hit8", true):
				_normal_attack()
		elif running and is_on_floor() and state == State.MOVE and _try_skill(&"hit6"):
			pass
		else:
			_normal_attack()
	if Input.is_action_just_pressed("skill_u"):
		_try_skill(&"hit7")
	elif Input.is_action_just_pressed("skill_i"):
		_try_skill(&"hit9")
	elif Input.is_action_just_pressed("skill_o"):
		_try_skill(&"hit10")
	if Input.is_action_just_pressed("rage"):
		_try_transform()
	if Input.is_action_just_pressed("treasure") and is_instance_valid(treasure):
		treasure.use()

func _try_jump() -> void:
	if state != State.MOVE or jump_count >= 2:
		return
	jump_count += 1
	velocity.y = data.rage_jump_velocity if transformed else data.jump_velocity
	rig.play(&"jump1" if jump_count == 1 else &"jump2", true)

func _try_drop_through() -> void:
	if state != State.MOVE or not is_on_floor():
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i).get_collider()
		if c is CollisionObject2D and c.collision_layer & LAYER_ONEWAY:
			collision_mask &= ~LAYER_ONEWAY
			_drop_t = DROP_THROUGH_TIME
			position.y += data.drop_through
			jump_count = 1
			rig.play(&"jump1")
			return

# ------------------------------------------------------------------ attacks

## Input accepted while idle, or mid-combo once the cooldown is over (the original has no input buffer).
func _can_act() -> bool:
	return cooldown <= 0.0 and (state == State.MOVE or (state == State.ATTACK and attack_action in COMBO))

func _normal_attack() -> void:
	if not _can_act():
		return
	if not is_on_floor():
		cooldown = data.air_cooldown
		combo_step = 0
		_begin(&"hit3")
		return
	if _clock - _last_attack_at > data.combo_reset:
		combo_step = 0
	_last_attack_at = _clock
	cooldown = data.combo_cooldowns[combo_step]
	var action: StringName = COMBO[combo_step]
	combo_step = (combo_step + 1) % COMBO.size()
	_begin(action)

func _try_skill(action: StringName, cancel := false) -> bool:
	var a: AttackData = data.attacks.get(action)
	if a == null or not GameState.has_skill(action) or mp < a.mp_cost:
		return false
	var allowed := state == State.MOVE and cooldown <= 0.0
	if cancel and state == State.ATTACK and attack_action in CANCEL_INTO_HIT8 and rig.progress() >= data.cancel_progress:
		allowed = true
	if not allowed:
		return false
	mp -= a.mp_cost
	cooldown = a.cooldown
	if action == &"hit8" and not is_on_floor():
		jump_count = 2
	_begin(action)
	return true

func _begin(action: StringName) -> void:
	state = State.ATTACK
	start_attack(action, data.attacks.get(action))
	Snd.sfx(SOUNDS.get(action, ""))
	match action:
		&"hit6":
			velocity.x = facing * (attack.rage_dash_speed if transformed else attack.dash_speed)
			running = false   # the dash ends in a walk
		&"hit10":
			invincible = maxf(invincible, attack.invincible)

func _update_velocity() -> void:
	var speed := (data.run_speed if running else data.walk_speed) * (data.rage_speed_mul if transformed else 1.0)
	match state:
		State.MOVE:
			velocity.x = _dir * speed
			if _dir != 0:
				facing = _dir
		State.ATTACK:
			if attack_action in SCRIPTED_MOTION:
				# hit10 is rooted once it lands (its dive speed must not carry into a slide)
				if attack_action == &"hit10" and is_on_floor() and not _no_gravity:
					velocity.x = 0.0
			elif attack_action == &"hit8" or (attack_action == &"hit3" and not is_on_floor()):
				velocity.x = _dir * data.walk_speed * (data.rage_speed_mul if transformed else 1.0)
			elif is_on_floor():
				velocity.x = 0.0

func _after_move() -> void:
	if is_on_floor() and velocity.y >= 0.0:
		jump_count = 0
		if _hit10_down:
			_hit10_slam()
	if state == State.MOVE:
		_pick_move_anim()

func _pick_move_anim() -> void:
	if is_on_floor():
		if _dir == 0:
			rig.play(&"wait")
		else:
			rig.play(&"run" if running else &"walk")
	elif rig.action == &"jump2" and rig.is_playing():
		pass
	elif velocity.y < 0.0:
		rig.play(&"jump1")
	else:
		rig.play(&"jump3")

func _clamp_to_view() -> void:
	var v := world.view_rect()
	global_position.x = clampf(global_position.x, v.position.x + world.edge_margin,
		v.end.x - world.edge_margin)

# ------------------------------------------------------------------ animation events

func _on_rig_event(n: StringName, args: Array) -> void:
	match n:
		&"finished":
			_finish_action(rig.action)
		&"set_vx":
			velocity.x = args[0]
		&"set_vy":
			velocity.y = args[0]
		&"set_vx_forward":
			velocity.x = facing * args[0]
		&"scale_vx":
			velocity.x *= args[0]
		&"stop_move":
			velocity.x = 0.0
		&"new_hit":
			dealer.new_serial()
		&"call", &"grounded_call":
			if n == &"grounded_call" and not is_on_floor():
				return
			match args[0]:
				"add_fire_effect":
					Fx.spawn("fx_hit7_fire", global_position, facing)   # mirrors with the hero
					velocity.x = facing * attack.dash_speed
					invincible = maxf(invincible, attack.invincible)
				"set_lost_graity":
					_no_gravity = true
				"set_lost_keyboard":
					_no_input = true
				"add_hit10_pre":
					Fx.spawn("fx_hit10_pre", global_position + Vector2(0, 20), -facing)   # art faces the other way
				"add_hit10_and1":
					_hit10_seek()
				"add_hit10_flush":
					var p := _skill_projectile("wukong_hit10_flush", &"hit10_3", global_position)
					p.facing = -facing   # art faces the other way
					invincible = maxf(invincible, data.attacks[&"hit10"].extra.flush_invincible)
					_hit10_down = true
				"add_hit10_and2":
					_hit10_slam()

func _skill_projectile(rig_name: String, action: StringName, pos: Vector2) -> Projectile:
	var p := Projectile.create(rig_name, self, data.attacks[action], action)
	p.position = pos
	world.add_object(p)
	return p

## hit10 frame 7: teleport onto the nearest on-screen enemy and combo it, else skip to the dive.
func _hit10_seek() -> void:
	var ex: Dictionary = data.attacks[&"hit10"].extra
	var v := world.view_rect()
	for m in world.monsters():
		if not m.can_be_hit():
			continue
		var r: Rect2 = m.hurt_rect()
		if r.position.x > v.position.x + 20 and r.position.x < v.end.x - 20 \
				and m.global_position.distance_to(global_position) <= ex.seek_radius:
			Snd.sfx("Role1_hit10_2")
			_skill_projectile("wukong_hit10_1", &"hit10_1", m.global_position)
			global_position = m.global_position + Vector2(0, -2)
			reset_physics_interpolation()
			cooldown = ex.seek_cooldown
			return
	rig.seek_to_event(&"call", "add_hit10_flush")

func _hit10_slam() -> void:
	if not _hit10_down:
		return
	_hit10_down = false
	_no_gravity = false
	var ex: Dictionary = data.attacks[&"hit10"].extra
	Snd.sfx("Role1_hit10_3")
	var p := _skill_projectile("wukong_hit10_2", &"hit10_2", global_position)
	var s: float = ex.rage_slam_scale if transformed else ex.slam_scale
	p.rig.scale = Vector2(s, s)
	cooldown = ex.slam_cooldown

func _finish_action(action: StringName) -> void:
	if action != rig.action:
		return
	match state:
		State.ATTACK:
			_no_gravity = false
			_no_input = false
			_hit10_down = false
			end_attack()
			state = State.MOVE
			_pick_move_anim()
		State.HURT:
			state = State.MOVE
			_pick_move_anim()
		State.MOVE:
			if action == &"jump2":
				rig.play(&"jump3")

func _on_action_finished(action: StringName) -> void:
	_finish_action(action)

# ------------------------------------------------------------------ damage

## Skill power x rage form (x1.5) x crit (x2), as Role1.getRealPower.
func outgoing_damage(a: AttackData) -> int:
	var dmg := a.flat if a.flat > 0 else roundi(GameState.attack_power() * a.power_mul)
	if transformed:
		dmg = roundi(dmg * 1.5)
	last_crit = Rng.randf() < GameState.crit()
	if last_crit:
		dmg *= 2
	return dmg

## Equipment regen: +hp_regen / +mp_regen every regen interval.
var _regen_t := 0.0

func _update_regen(delta: float) -> void:
	if state == State.DEAD:
		return
	_regen_t += delta
	var interval := EquipmentCatalog.get_catalog().regen_interval
	if _regen_t >= interval:
		_regen_t -= interval
		hp = mini(hp + GameState.hp_regen(), max_hp)
		mp = mini(mp + GameState.mp_regen(), max_mp)

func take_hit(h: Hit) -> bool:
	if not can_be_hit():
		return false
	if Rng.randf() < GameState.miss():
		DamageNumber.spawn_miss(global_position + Vector2(-20, -60))
		return true
	var dmg := h.mitigated(GameState.defense(), GameState.bonus("mdef")) + Rng.randi_range(-5, 5)
	dmg = maxi(1, dmg)
	hp = maxi(hp - dmg, 0)
	DamageNumber.spawn("pnum", dmg, global_position + Vector2(-20, -60))
	_apply_effects(h.attack.effects)
	Fx.spawn("fx_hero_hurt", center())
	Snd.sfx("Role1_beAttack")
	add_rage(roundi(dmg * data.rage_hit_gain / maxf(GameState.attack_power(), 1.0)))
	_count_lock()
	if hp <= 0:
		_die()
		return true
	if transformed:
		return true   # super armor: damage only, no knockback or hit stun (Role1.beAttackDoing)
	velocity = Vector2(h.attack.knockback.x * h.direction, h.attack.knockback.y)
	if state == State.HURT:
		rig.play(&"hurt", true)
	else:
		state = State.HURT
		end_attack()
		_no_gravity = false
		_no_input = false
		rig.play(&"hurt", true)
	return true

## 5 hits within the window grant a short invincibility (the "father" buff).
func _count_lock() -> void:
	if _clock - _last_hurt_at >= data.lock_window:
		_lock_count = 0
	_last_hurt_at = _clock
	_lock_count += 1
	if _lock_count >= data.lock_hits:
		_lock_count = 0
		invincible = data.lock_invincible
		_lock_glow = data.lock_invincible

## 孟婆's magiclost: every px the hero moves sideways costs MAGICLOST_MP_PER_PX MP (BaseAddEffect: speed.x * 2 a frame).
const MAGICLOST_MP_PER_PX := 2.0
var _mp_drain := 0.0

func _drain_mp_by_moving() -> void:
	_mp_drain += absf(velocity.x) * get_physics_process_delta_time() * MAGICLOST_MP_PER_PX
	var n := int(_mp_drain)
	if n > 0:
		_mp_drain -= n
		mp = maxi(mp - n, 0)

## Status icons shown on the hero (BaseAddEffect.showXxx): debuff -> [rig, offset].
func add_debuff(n: StringName, seconds: float) -> void:
	debuffs.add(n, seconds)

func clear_debuff(n: StringName) -> void:
	debuffs.clear(n)

## Status effects from a monster attack (poison damages every tick).
func _apply_effects(effects: Array) -> void:
	for e in effects:
		add_debuff(StringName(e.name), e.time)
		if e.name == "poison":
			_poison = [float(e.power), float(e.tick), 0.0]

## Input is locked while grabbed, petrified by a gaze or caught in a net.
func input_locked() -> bool:
	return controls_locked or held_by != null or has_debuff(&"eyefix") or has_debuff(&"net")

func has_debuff(n: StringName) -> bool:
	return debuffs.has(n)

## Damage that ignores defence and invincibility (totems, reflected damage, drains).
func lose_hp(amount: int) -> void:
	if state == State.DEAD or amount <= 0:
		return
	hp = maxi(hp - amount, 0)
	DamageNumber.spawn("pnum", amount, global_position + Vector2(-20, -60))
	if hp <= 0:
		_die()

func heal(amount: int, show_number := true) -> void:
	if amount <= 0 or state == State.DEAD:
		return
	hp = mini(hp + amount, max_hp)
	if show_number:
		DamageNumber.spawn("bunum", amount, global_position + Vector2(-20, -60))

func restore_mp(amount: int) -> void:
	mp = mini(mp + amount, max_mp)

func add_rage(amount: int) -> void:
	if transformed:
		return
	rage = clampi(rage + amount, 0, data.rage_max)

func _update_rage(delta: float) -> void:
	_rage_t += delta
	if transformed:
		# every drain tick: -1 rage and an afterimage (BaseHero.stepOther / shadowEffect)
		if _rage_t >= data.rage_drain_interval:
			_rage_t = 0.0
			rage -= 1
			_spawn_afterimage()
			if rage <= 0:
				_end_transform()
	elif rage < data.rage_max and _rage_t >= data.rage_decay_interval:
		_rage_t = 0.0
		rage = maxi(rage - 1, 0)

func _try_transform() -> void:
	if transformed or rage < data.rage_max or state == State.DEAD:
		return
	transformed = true
	gravity = data.rage_gravity
	world.rage_transform(data.rage_freeze)

func _end_transform() -> void:
	transformed = false
	rage = 0
	gravity = data.gravity

## Afterimage of the current pose that fades out behind the hero.
func _spawn_afterimage() -> void:
	var ghost := rig.make_ghost()
	if ghost == null:
		return
	world.add_object(ghost)
	ghost.z_index = z_index - 1
	var tw := ghost.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_FADE)
	tw.tween_callback(ghost.queue_free)

## Anti-lock protection = pulsing glow.
func _update_tint(delta: float) -> void:
	var c := Color.WHITE
	if _lock_glow > 0.0:
		_lock_glow -= delta
		var pulse := 0.5 + 0.5 * sin(_clock * TAU * 2.0)
		c = c.lerp(Color(1.6, 1.6, 1.3), pulse * 0.6)
	rig.modulate = c

## 苍生挂饰: come back once with half HP / MP and a short invincibility (not when falling out of the stage).
func _try_revive() -> bool:
	var rv: Dictionary = EquipmentCatalog.get_catalog().revive
	if rv.is_empty() or global_position.y >= float(rv.max_y) or not GameState.consume_revive():
		return false
	hp = int(max_hp * float(rv.ratio))
	mp = int(max_mp * float(rv.ratio))
	invincible = maxf(invincible, float(rv.invincible))
	return true

func _die() -> void:
	if _try_revive():
		return
	state = State.DEAD
	end_attack()
	velocity = Vector2.ZERO
	Snd.sfx("Role1_dead")
	rig.visible = false
	_drop_tomb()
	died.emit(self)
## Original heroDead: the hero disappears and a gravestone falls where they stood (deadmb, 10 px above).
func _drop_tomb() -> void:
	var tomb := Rig.create("hero_tomb")
	tomb.position = global_position + Vector2(0, -10)
	tomb.z_index = Layers.Z_HERO
	world.add_object(tomb)
	tomb.play(tomb.actions[0])   # stays on its last frame
