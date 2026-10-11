class_name Monster
extends Actor
## A monster body: movement, getting hit, death and loot. Decisions come from its MonsterBrain
## (base AI, a shared boss template, or a per-monster script chosen by MonsterData.brain).

signal destroyed(monster: Monster)

enum State { MOVE, ATTACK, HURT, DEAD }


var data: MonsterData
var brain: MonsterBrain
var state := State.MOVE
var target: Hero
var dir := 0                  ## walk direction chosen by the brain (-1, 0, 1)
var fly := false              ## no gravity; the brain sets velocity.y
var invuln := 0.0             ## immune to all damage (setYourFather)
var super_armor := false      ## hits do not interrupt (no hurt state / knockback)
var cds := {}                 ## named cooldowns (s), counted down every tick
var summoner: Monster         ## the monster that created this one
var _hp_bar_t := 0.0
var _hp_bar: Node2D
var _vanishing := false

static func create(d: MonsterData) -> Monster:
	var m := Monster.new()
	m.data = d
	return m

func _ready() -> void:
	gravity = data.gravity
	collision_layer = LAYER_MONSTER
	z_index = Layers.Z_MECHANISM if data.behind else Layers.Z_MONSTER
	collision_mask = LAYER_WORLD | LAYER_ONEWAY
	brain = MonsterBrain.create(self)   # before the rig: its first action already emits events
	setup_rig(data.rig)
	max_hp = data.hp
	hp = max_hp
	facing = -1
	_hp_bar = Node2D.new()
	_hp_bar.draw.connect(_draw_hp_bar)
	_hp_bar.visible = false
	add_child(_hp_bar)
	if rig.actions.has("walk"):
		rig.play(&"walk")
	brain.setup()

var _stun_t := 0.0
var _stun_fx: Rig

## 眩晕 (BaseAddEffect "stun"): the monster stands still, no AI, no attacks.
func stun(seconds: float) -> void:
	if state == State.DEAD or data.is_prop:
		return
	_stun_t = maxf(_stun_t, seconds)
	if state == State.ATTACK or state == State.HURT:
		end_attack()
		state = State.MOVE
	dir = 0
	if _stun_fx == null:
		_stun_fx = Rig.create("fx_stun")
		_stun_fx.position = Vector2(0, hurt_rect().position.y - global_position.y - 10.0)
		_stun_fx.scale = Vector2(0.4, 0.4)
		add_child(_stun_fx)
		_stun_fx.play(_stun_fx.actions[0])
		_stun_fx.action_finished.connect(func(a): _stun_fx.play(a, true))

func can_be_hit() -> bool:
	return state != State.DEAD and invuln <= 0.0 and brain.can_be_hit()

func _physics_process(delta: float) -> void:
	dealer.tick(delta)
	invuln = maxf(invuln - delta, 0.0)
	for k in cds:
		cds[k] = maxf(cds[k] - delta, 0.0)
	if _hp_bar_t > 0.0:
		_hp_bar_t -= delta
		_hp_bar.modulate.a = clampf(_hp_bar_t / data.hp_bar_fade, 0.0, 1.0)
		_hp_bar.visible = _hp_bar_t > 0.0
	if target and not target.is_alive():
		target = null
	_tick_poison(delta)
	if _stun_t > 0.0:
		_stun_t -= delta
		velocity.x = 0.0
		if _stun_t <= 0.0 and _stun_fx:
			_stun_fx.queue_free()
			_stun_fx = null
	elif state != State.DEAD:
		brain.think(delta)
	if _stun_t <= 0.0:
		_apply_motion(delta)
	if not fly:
		apply_gravity(delta)
	move_and_slide()
	if state == State.ATTACK:
		scan_hits()
	if state == State.MOVE and not brain.custom_animation():
		rig.play(&"walk" if dir != 0 and rig.actions.has("walk") else &"wait")
	if global_position.y > Hero.FALL_DEATH_Y:
		vanish()

func _apply_motion(delta: float) -> void:
	match state:
		State.MOVE:
			if not fly and dir == 0 and not is_on_floor():
				# in the air with no walking intention (knocked up): the sideways speed carries on to the landing, an arc
				if absf(velocity.x) > data.speed:
					velocity.x *= pow(data.knockback_decay, delta)
					if absf(velocity.x) < data.speed:
						velocity.x = signf(velocity.x) * data.speed
			else:
				velocity.x = dir * brain.move_speed()
			if dir != 0:
				facing = dir
		State.ATTACK:
			# attacks root the monster unless the move lunges (velocity then comes from animation events)
			if not (attack_action in data.move_while_attacking) and not brain.moves_while_attacking():
				velocity.x = 0.0
		_:
			# knock-back slide decays toward walk speed, then keeps sliding at walk speed (adjustSpeed)
			if absf(velocity.x) > data.speed:
				velocity.x *= pow(data.knockback_decay, delta)
				if absf(velocity.x) < data.speed:
					velocity.x = signf(velocity.x) * data.speed

# ------------------------------------------------------------------ helpers for brains

func cd(key: String) -> float:
	return cds.get(key, 0.0)

func set_cd(key: String, seconds: float) -> void:
	cds[key] = seconds

func face(pos: Vector2) -> void:
	facing = 1 if pos.x > global_position.x else -1

func face_target() -> void:
	if target:
		face(target.global_position)

func to_target() -> Vector2:
	return target.global_position - global_position if target else Vector2.INF

func is_attacking() -> bool:
	return state == State.ATTACK

func is_hurt() -> bool:
	return state == State.HURT

## Start an attack action using the attack data of the same name (or `attack_key`).
func attack_with(action: StringName, attack_key: StringName = &"") -> bool:
	if not rig.actions.has(String(action)):
		return false
	dir = 0
	state = State.ATTACK
	var key := attack_key if attack_key != &"" else action
	start_attack(action, data.attacks.get(key, data.attacks.get(&"hit1")))
	return true

## Play a non-attack action (intro, transform...) that returns to MOVE when it finishes.
func play_action(action: StringName) -> void:
	if not rig.actions.has(String(action)):
		return
	dir = 0
	state = State.ATTACK
	attack = null
	attack_action = action
	rig.play(action, true)

## Spawn a projectile / effect that hits with the attack data `key`.
## offset.x is in front of the monster; velocity.x is forward speed (px/s).
func shoot(rig_name: String, key: StringName, offset := Vector2.ZERO, vel := Vector2.ZERO, distance := 0.0) -> Projectile:
	var a: AttackData = data.attacks.get(key, attack)
	var p := Projectile.create(rig_name, self, a, key)
	p.position = global_position + Vector2(offset.x * facing, offset.y)
	p.facing = facing
	p.velocity = Vector2(vel.x * facing, vel.y)
	p.distance_left = distance
	world.add_object(p)
	return p

## Create another monster (summons, form changes). Returns null when the data is missing.
func summon(id: int, pos: Vector2) -> Monster:
	var md := world.monster_data(id)
	if md == null:
		push_warning("monster %d: no data" % id)
		return null
	var m := Monster.create(md)
	m.position = pos
	m.summoner = self
	world.add_monster(m)
	return m

## Poison (BaseAddEffect POISON, 罗刹妖伞): `power` damage every `tick` for `seconds`; icon over the head.
var _poison := {}
var _poison_icon: Rig

func add_poison(power: int, seconds: float, tick: float) -> void:
	if state == State.DEAD:
		return
	_poison = {"power": power, "left": seconds, "tick": tick, "t": 0.0}
	if _poison_icon == null:
		_poison_icon = _status_icon("fx_poison_head", -70.0, true)
		_status_icon("fx_poison_up", -50.0, false)

func _status_icon(rig_name: String, y: float, loop: bool) -> Rig:
	var r := Rig.create(rig_name)
	r.position = Vector2(0, y)
	add_child(r)
	r.play(r.actions[0])
	r.action_finished.connect(func(a): r.play(a, true) if loop else r.queue_free())
	return r

func _tick_poison(delta: float) -> void:
	if _poison.is_empty():
		return
	_poison.left -= delta
	_poison.t += delta
	if _poison.t >= _poison.tick:
		_poison.t -= _poison.tick
		hurt_directly(int(_poison.power))
	if _poison.left <= 0.0 or state == State.DEAD:
		_poison = {}
		if is_instance_valid(_poison_icon):
			_poison_icon.queue_free()
		_poison_icon = null

## Damage that ignores defence, with its number (drains, poison).
func hurt_directly(amount: int) -> void:
	if state == State.DEAD or amount <= 0 or not brain.can_be_hit():
		return
	DamageNumber.spawn("hurtnum", amount, Vector2(global_position.x - 20, hurt_rect().position.y), 20.0)
	damage_directly(amount)
	if not data.is_prop and not data.is_boss:
		_hp_bar_t = data.hp_bar_time
		_hp_bar.visible = true
		_hp_bar.queue_redraw()

func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)

func damage_directly(amount: int) -> void:
	if state == State.DEAD:
		return
	hp = maxi(hp - amount, 0)
	if hp <= 0:
		_die()

func outgoing_damage(a: AttackData) -> int:
	return brain.outgoing_damage(a)

# ------------------------------------------------------------------ animation events

func _on_rig_event(n: StringName, args: Array) -> void:
	if brain.on_event(n, args):
		return
	match n:
		&"finished":
			_on_action_finished(rig.action)
		&"set_vx_forward":
			velocity.x = facing * args[0]
		&"set_vx":
			velocity.x = args[0]
		&"set_vy":
			velocity.y = args[0]
		&"scale_vx":
			velocity.x *= args[0]
		&"stop_move":
			velocity.x = 0.0
		&"new_hit":
			dealer.new_serial()
		&"call":
			if brain.on_call(String(args[0]), args.slice(1)):
				return
			match args[0]:
				"do_hit1", "do_hit2", "do_hit3":
					# data-driven projectile of the current attack (monsters.json "spawn")
					if attack and attack.projectile != "":
						fire_projectile(attack, attack_action)
				"drop_aura":
					Loot.drop(self)
				"destroy":
					if state == State.DEAD:
						Loot.drop(self)   # a death clip that only destroys (楚江王): the loot comes with it
					vanish()
		&"boss_dead_fx":
			boss_dead_sequence()
		&"shake":
			world.shake(float(args[0]))

## BossDead (Common_v7; a brain whose last death clip has no drop of its own starts it too): a full-screen swirl; at its end every dead boss drops loot and is removed.
var _boss_dead_started := false

func boss_dead_sequence() -> void:
	if _boss_dead_started:
		return
	_boss_dead_started = true
	rig.visible = false
	var fx := Fx.spawn("fx_boss_dead", center())
	fx.tree_exited.connect(func():
		if is_instance_valid(self) and not _vanishing:
			Loot.drop(self)
			vanish(), CONNECT_DEFERRED)

## An action ends as if its clip had finished (brains whose action is cut short by their own logic).
func finish_action(action: StringName) -> void:
	_on_action_finished(action)

func _on_action_finished(action: StringName) -> void:
	if action != rig.action:
		return
	match state:
		State.ATTACK:
			end_attack()
			state = State.MOVE
			brain.on_action_finished(action)
		State.HURT:
			if is_on_floor() or fly:
				velocity.x = 0.0   # (in the air the knock-back carries on to the landing)
			state = State.MOVE
		State.DEAD:
			if not _boss_dead_started:   # (a boss waits for its death swirl to finish)
				vanish()

# ------------------------------------------------------------------ damage

func take_hit(h: Hit) -> bool:
	if not can_be_hit():
		return false
	var dmg := h.mitigated(data.def, data.mdef)
	dmg = brain.modify_damage(h, dmg)
	hp = maxi(hp - dmg, 0)
	if h.source is Hero:
		target = h.source
		world.add_combo_hit()
		h.source.add_rage((h.source as Hero).rage_for_damage(dmg))
		if h.attack.kind == AttackData.Kind.PHYSICS and GameState.bonus("lifesteal") > 0.0:
			h.source.heal(int(dmg * GameState.bonus("lifesteal")))   # (BaseHero.cureHp: the green number over the hero)
	Snd.sfx(h.source.hit_sound if h.source is Hero else "BeattackByRole1")
	rig.flash(Color.WHITE, 0.09)
	Fx.spawn("fx_monster_hurt1" if Rng.randf() < 0.5 else "fx_monster_hurt2", center())
	if not data.is_prop:
		DamageNumber.spawn("bnum" if h.crit else "hurtnum", dmg,
			Vector2(global_position.x - 20, hurt_rect().position.y), 16.0 if h.crit else 20.0)
		_hp_bar_t = data.hp_bar_time
		_hp_bar.visible = true
		_hp_bar.queue_redraw()
	brain.on_hit(h, dmg)
	if hp <= 0:
		_die()
		return true
	if super_armor or brain.ignores_hit(h):
		return true
	if not data.immovable:
		velocity = Vector2(h.attack.knockback.x * h.direction, h.attack.knockback.y)
	end_attack()
	brain.on_hurt_start()
	if rig.actions.has("hurt"):
		state = State.HURT
		rig.play(&"hurt", true)
	else:
		state = State.MOVE
	return true

func _die() -> void:
	if state == State.DEAD:
		return
	if brain.intercept_death():
		return   # revives / transforms instead (the brain drives what happens)
	state = State.DEAD
	end_attack()
	velocity.x = 0.0
	GameState.add_exp(data.exp)
	brain.on_died()
	if rig.actions.has("dead"):
		rig.play(&"dead", true)
		# a death pose that never ends (a single looping frame, no script): it fades out quickly instead of staying
		var an := rig.anim.get_animation(&"dead")
		if an != null and an.loop_mode != Animation.LOOP_NONE and not an.has_meta(&"loop_from") and not rig.has_events(&"dead"):
			Loot.drop(self)
			vanish(0.4)
	else:
		Loot.drop(self)
		vanish()
	died.emit(self)

## Run `fn` after `sec` seconds of game time. The timer belongs to this monster: when it is freed first, the call never
## happens (no stale callback meets a dead boss).
func after(sec: float, fn: Callable) -> void:
	var tw := create_tween()
	tw.tween_interval(sec)
	tw.tween_callback(fn)

## `fn` wrapped so that it only runs while this monster still exists: for callbacks hung on other objects (effects,
## projectiles) that can outlive the monster that made them.
func owned(fn: Callable) -> Callable:
	var ref: WeakRef = weakref(self)
	return func(...args: Array) -> void:
		if ref.get_ref() != null:
			fn.callv(args)

## Fade out and free (no death animation, no loot).
func vanish(fade := 0.3) -> void:
	if _vanishing:
		return
	_vanishing = true
	brain.on_destroy()
	destroyed.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade)
	tw.tween_callback(queue_free)

func _draw_hp_bar() -> void:
	if data.is_boss:
		return   # bosses show their bar on the HUD
	var box := rig.hurtbox.get_child(0) as CollisionShape2D
	var y: float = box.position.y - box.shape.size.y / 2.0 - 10.0
	var w := 50.0
	_hp_bar.draw_rect(Rect2(-w / 2.0, y, w, 5), Color(0, 0, 0, 0.8))
	_hp_bar.draw_rect(Rect2(-w / 2.0 + 0.5, y + 0.5, (w - 1.0) * float(hp) / max_hp, 4), Color(0.9, 0.1, 0.1))
