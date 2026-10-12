class_name Hero
extends Actor
## A playable hero. This base class is Wukong: input, movement, 5-hit combo, skills (hit6-hit10), rage transform,
## getting hit. 唐僧 and 八戒 extend it (src/actors/heroes/) and override the hooks marked "virtual".
## Numbers come from HeroData (baked from the original, px / seconds).

enum State { MOVE, ATTACK, HURT, DEAD }

const HERO_DIR := "res://src/actors/heroes/hero_%s.gd"
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
var combo_actions: Array = COMBO       ## normal attack chain (virtual: 八戒 has three)
var sounds: Dictionary = SOUNDS         ## action -> sound (virtual)
var hit_sound := "BeattackByRole1"      ## played on the monster when this hero hits it
var state := State.MOVE
var mp := 0
var max_mp := 0
var rage := 0.0           ## fractional like the original (wsValue)
var _last_attack_data: AttackData   ## the hero's own last move (original lastHit): its power scales the rage a hit gives
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
var _hit10_land := false   ## 火魔斩's animation has run out while he is still falling: the move waits for the landing
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

## The hero of the current game (GameState.role): its own script when it has one.
static func create() -> Hero:
	var path: String = HERO_DIR % GameState.role
	return load(path).new() if ResourceLoader.exists(path) else Hero.new()

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
## With the 脱衣回蓝 trick switched on (GameState.strip_trick, key F) they work as in the original: taking gear off
## subtracts its bonus from the current value (HP: down to 1 at least), putting it on adds it, and the value is only
## clamped to 0..max at the next regeneration tick - so a bonus taken off at zero is "lost" only on paper and comes back
## in full when the gear goes on again.
func _on_equipment_changed() -> void:
	_apply_appearance()
	_sync_treasure()
	var old_hp := max_hp
	var old_mp := max_mp
	max_hp = GameState.max_hp()
	max_mp = GameState.max_mp()
	if GameState.strip_trick:
		var dh := max_hp - old_hp
		hp = 1 if (dh < 0 and -dh > hp) else hp + dh
		mp += max_mp - old_mp
		return
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
	return state != State.DEAD and invincible <= 0.0 and not GameState.debug_god

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
		# grabbed / petrified (setStatic): rooted and standing, not sliding or walking on
		velocity.x = 0.0
		_dir = 0
		running = false
	if has_debuff(&"net"):
		# BaseHero.move(): caught in the net the hero neither walks nor falls; attacks and treasures still work
		velocity = Vector2.ZERO
	else:
		if not _no_gravity:
			apply_gravity(delta)
		move_and_slide()
	_after_move()
	_clamp_to_view()
	if state == State.ATTACK:
		scan_hits()
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
	_read_attack_input()
	if Input.is_action_just_pressed("rage"):
		_try_transform()
	if Input.is_action_just_pressed("treasure") and is_instance_valid(treasure):
		treasure.use()

## Attack and skill keys (virtual).
func _read_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		# up+attack: nothing until 升龙斩 is learned (Role1 "0101"); without MP it falls back to a normal hit
		if Input.is_action_pressed("move_up"):
			if GameState.has_skill(&"hit8") and not _try_skill(&"hit8", true):
				_normal_attack()
		elif running and is_on_floor() and state == State.MOVE and _try_skill(&"hit6"):
			pass
		else:
			_normal_attack()
	# holding a skill key repeats it (the original gets key repeat from the keyboard): 烈焰风暴 and the others
	# cast again as soon as the move is over
	if Input.is_action_pressed("skill_u"):
		_try_skill(&"hit7")
	elif Input.is_action_pressed("skill_i"):
		_try_skill(&"hit9")
	elif Input.is_action_pressed("skill_o"):
		_try_skill(&"hit10")

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

## Actions a new normal attack may cut short (virtual).
func _cancelable_actions() -> Array:
	return combo_actions

## Input accepted while idle, or mid-combo once the cooldown is over (the original has no input buffer).
func _can_act() -> bool:
	return cooldown <= 0.0 and (state == State.MOVE or (state == State.ATTACK and attack_action in _cancelable_actions()))

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
	var action: StringName = combo_actions[combo_step]
	combo_step = (combo_step + 1) % combo_actions.size()
	_begin(action)

func _try_skill(action: StringName, cancel := false) -> bool:
	var a: AttackData = data.attacks.get(action)
	if a == null or not GameState.has_skill(action) or mp < a.mp_cost:
		return false
	# skills only wait for the move to end: the original input lock (timers) only holds back the normal attack,
	# so 升龙斩 flows straight into 火魔斩 etc. (the lock still starts, for the next normal hit)
	var allowed := state == State.MOVE
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
	if action == &"hit7" and transformed:
		_spawn_afterimage()   # the one afterimage of the dash, in the pose it starts from
	state = State.ATTACK
	_last_attack_data = data.attacks.get(action)
	start_attack(action, data.attacks.get(action))
	Snd.sfx(sounds.get(action, ""))
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
			_attack_motion()

## Horizontal motion while an attack plays (virtual).
func _attack_motion() -> void:
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
		if _hit10_land:   # the slam has come out: now the move is over
			_hit10_land = false
			_finish_action(attack_action)
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
			_on_new_hit()
		&"call", &"grounded_call":
			if n == &"grounded_call" and not is_on_floor():
				return
			match args[0]:
				"add_fire_effect":
					if attack == null:   # the move was cut short (hit, ...) in the same frame
						return
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
					if is_on_floor():   # in the air the slam waits for the landing (see _hit10_land)
						_hit10_slam()
				_:
					_on_hero_call(String(args[0]), args)

## A new round of hits starts inside the current move (virtual).
func _on_new_hit() -> void:
	pass

## Frame-script calls the base class does not know (virtual): the extractor names them snake_case, e.g. "do_hit1".
func _on_hero_call(_name: String, _args: Array) -> void:
	pass

func _skill_projectile(rig_name: String, action: StringName, pos: Vector2) -> Projectile:
	var p := Projectile.create(rig_name, self, data.attacks[action], action)
	p.position = pos
	p.facing = facing   # a bullet is flipped to the way its caster faces (BaseBullet.setRole)
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
			_skill_projectile("wukong_hit10_1", &"hit10_1", m.global_position).push_dir = facing   # the combo drives the target the way he faces
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
			if action == &"hit10" and _hit10_down and not is_on_floor():
				# dived from so high that the animation ended in the air: hold the last frame until he lands, then slam
				_hit10_land = true
				return
			_hit10_land = false
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
		hp = clampi(hp + GameState.hp_regen(), 0, max_hp)
		mp = clampi(mp + GameState.mp_regen(), 0, max_mp)   # (BaseRoleProperies.setMMP: also what clears a negative value)

func take_hit(h: Hit) -> bool:
	if not can_be_hit():
		return false
	if Rng.randf() < GameState.miss():
		DamageNumber.spawn_miss(global_position + Vector2(-20, -60))
		return true
	if h.attack.effect_only:
		var id := h.carrier.get_instance_id() if h.carrier != null else 0
		if _cured_carriers.has(id):
			return false   # this very net already let go of us
		_effect_carrier = id
		_apply_effects(h.attack.effects)
		return true
	h.damage += int((Rng.randf() - 0.5) * 10.0)   # BaseHero.beAttack: noise (-4..4, truncated) before defense
	var dmg := h.mitigated(GameState.defense(), GameState.bonus("mdef"))
	dmg = maxi(1, dmg)
	if transformed and data.damage_taken_mul_in_rage != 1.0:
		dmg = maxi(1, int(dmg * data.damage_taken_mul_in_rage))
	dmg = _adjust_incoming(h, dmg)
	hp = maxi(hp - dmg, 0)
	DamageNumber.spawn("pnum", dmg, global_position + Vector2(-20, -60))
	_apply_effects(h.attack.effects)
	rig.flash(Color(1.0, 0.35, 0.3), 0.12)
	Fx.spawn("fx_hero_hurt", center())
	Snd.sfx(data.sound_prefix + "_beAttack")
	add_rage(rage_for_damage(dmg))
	_count_lock()
	if hp <= 0:
		_die()
		return true
	_after_damage(h, dmg)
	if (transformed and data.super_armor_in_rage) or _super_armor():
		return true   # super armor: damage only, no knockback or hit stun (Role1.beAttackDoing)
	velocity = Vector2(h.attack.knockback.x * h.direction, h.attack.knockback.y)
	if state == State.HURT:
		rig.play(&"hurt", true)
	else:
		state = State.HURT
		end_attack()
		_hit10_down = false
		_hit10_land = false
		_no_gravity = false
		_no_input = false
		rig.play(&"hurt", true)
	return true

## Damage after defense, before it is applied (virtual: 八戒's spinning guard).
func _adjust_incoming(_h: Hit, dmg: int) -> int:
	return dmg

## Called once the damage is taken (virtual: 八戒's reflecting stance).
func _after_damage(_h: Hit, _dmg: int) -> void:
	pass

## No hit stun or knockback right now (virtual).
func _super_armor() -> bool:
	return false

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

## 血海魔童 (cureDebuff): every debuff goes. A net that held us does not catch us again.
func cure_debuffs() -> void:
	if debuffs.has(&"net") and _effect_carrier != 0:
		_cured_carriers[_effect_carrier] = true
	debuffs.clear()

var _effect_carrier := 0          ## instance id of the net that caught us
var _cured_carriers := {}

## Status effects from a monster attack (poison damages every tick).
func _apply_effects(effects: Array) -> void:
	for e in effects:
		add_debuff(StringName(e.name), e.time)
		if e.name == "poison":
			_poison = [float(e.power), float(e.tick), 0.0]

## Input is locked while grabbed or petrified by a gaze.
func input_locked() -> bool:
	return controls_locked or held_by != null or has_debuff(&"eyefix")

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

## RoleInfo.addWs: rage = round(damage / power of the last move * 2); when that rounds to 0, damage / 8.
## (Treasure hits count too: the divisor is the hero's last move, not the treasure's own damage.)
func rage_for_damage(dmg: int) -> float:
	var a := _last_attack_data
	var power := float(a.flat) if a != null and a.flat > 0 else float(GameState.attack_power()) * (a.power_mul if a != null and a.power_mul > 0.0 else 1.0)
	if transformed:
		power *= 1.5
	if Rng.randf() < GameState.crit():
		power *= 2.0
	var r := roundi(float(dmg) / maxf(power, 1.0) * data.rage_hit_gain)
	return float(r) if r != 0 else float(dmg) / 8.0

func add_rage(amount: float) -> void:
	if transformed:
		return
	rage = clampf(rage + amount, 0.0, float(data.rage_max))

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
		rage = maxf(rage - 1.0, 0.0)

func _try_transform() -> void:
	if transformed or rage < data.rage_max or state == State.DEAD:
		return
	transformed = true
	gravity = data.rage_gravity
	world.rage_transform(data.rage_freeze)

func _end_transform() -> void:
	transformed = false
	rage = 0.0
	gravity = data.gravity

## Whether the rage afterimage is drawn now (virtual).
func _afterimage_allowed() -> bool:
	# 烈焰闪 leaves one afterimage, where it starts (the dash itself is a speed-streak drawing that must not be copied)
	return not (state == State.ATTACK and attack_action == &"hit7")

## Afterimage of the current pose that fades out behind the hero.
func _spawn_afterimage() -> void:
	if not _afterimage_allowed():
		return
	var ghost := rig.make_ghost()
	if ghost == null:
		return
	world.add_object(ghost)
	ghost.z_index = z_index - 1
	var tw := ghost.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_FADE)
	tw.tween_callback(ghost.queue_free)

## BaseAddEffect.myGlow: the rage form glows white, the anti-lock protection in the hero's colour (悟空 red, 唐僧 blue,
## 八戒 gold). The glow breathes: blur 15 -> 6 and back, one step per frame (18 frames a cycle), strength 1.5; it is full
## while the blur shrinks and 0.8 while it grows.
const GLOW_COLORS := {"Role1": Color(1, 0, 0), "Role2": Color(0, 0, 1), "Role3": Color(1, 0.8, 0.2)}
const GLOW_BLUR := Vector2(15.0, 6.0)
const GLOW_STRENGTH := 1.5
const GLOW_ALPHA_UP := 0.8
const GLOW_PERIOD := 0.75   ## 18 frames at the original 24 fps

var _glow_rig: Rig   ## the halo: a copy of the hero drawn behind, every sprite a blurred silhouette of one colour
var _glow_mat: ShaderMaterial
var _glow_t := 0.0

## BaseAddEffect.step: the glow exists while the rage form lasts or the anti-lock protection is on; both end it at once
## (cancelGlow). The short invincible windows of skills show none.
func _update_tint(delta: float) -> void:
	var color := Color.TRANSPARENT
	if state != State.DEAD:
		if transformed:
			color = Color.WHITE
		elif _lock_glow > 0.0:
			color = GLOW_COLORS.get(data.sound_prefix, Color.WHITE)
	if _lock_glow > 0.0:
		_lock_glow -= delta
	if color.a == 0.0:
		if _glow_rig != null:
			_glow_rig.visible = false
		_glow_t = 0.0
		return
	if _glow_rig == null:
		_make_glow()
	_glow_t = fmod(_glow_t + delta, GLOW_PERIOD)
	var ph := _glow_t / GLOW_PERIOD * 2.0   # 0..1 shrinking, 1..2 growing
	var down := ph < 1.0
	var t := ph if down else 2.0 - ph
	color.a = 1.0 if down else GLOW_ALPHA_UP
	SpriteFx.set_glow(_glow_mat, color, lerpf(GLOW_BLUR.x, GLOW_BLUR.y, t), GLOW_STRENGTH)
	_glow_rig.mirror(rig)
	for sp: Sprite2D in _glow_rig.find_children("*", "Sprite2D", true, false):
		if sp.material != _glow_mat:
			sp.material = _glow_mat

func _make_glow() -> void:
	_glow_mat = SpriteFx.glow_material(Color.WHITE, GLOW_BLUR.x, GLOW_STRENGTH, true)
	_glow_rig = Rig.create(data.rig)
	add_child(_glow_rig)
	move_child(_glow_rig, rig.get_index())   # behind the body
	_glow_rig.play(rig.action, true)
	_glow_rig.anim.pause()

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
	Snd.sfx(data.sound_prefix + "_dead")
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
