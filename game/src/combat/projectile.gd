class_name Projectile
extends Node2D
## Bullet / skill effect that deals damage with its rig's hit box (BaseBullet family).
## Moves by `velocity`, dies after `distance_left` px, when its animation finishes, or when its hits are spent.

var rig: Rig
var source: Actor
var attack: AttackData
var action: StringName
var velocity := Vector2.ZERO
var distance_left := 0.0      ## 0 = no distance limit
var accel := Vector2.ZERO     ## px/s^2 added to velocity (arcs)
var life := 0.0               ## > 0: removed after this many seconds
var mover: Callable           ## custom motion: mover.call(projectile, delta); replaces velocity motion
var on_hit: Callable          ## on_hit.call(target) after a hit lands
var damage_fn: Callable       ## fixed damage roll (magic treasures): no crit or rage bonus
var new_hit_limit := -1       ## >= 0: only this many "new hit" animation events count (a skill whose last rounds only exist in rage)
var _new_hits := 0
var push_dir := 0              ## != 0: always knock targets this way (±1) instead of away from the bullet
var age := 0.0
var dealer := HitDealer.new()
var facing := -1:
	set(v):
		facing = 1 if v >= 0 else -1
		if rig:
			rig.scale.x = -facing * absf(rig.scale.x)

static func create(rig_name: String, owner_actor: Actor, data: AttackData, act: StringName) -> Projectile:
	var p := Projectile.new()
	p.z_index = Layers.Z_EFFECT
	p.rig = Rig.create(rig_name)
	p.add_child(p.rig)
	p.source = owner_actor
	p.attack = data
	p.action = act
	p.rig.event.connect(p._on_event)
	p.rig.hitbox.collision_mask = Actor.LAYER_HURT_MONSTER if owner_actor is Hero else Actor.LAYER_HURT_HERO
	p.rig.action_finished.connect(func(_a): p.queue_free())
	return p

func _ready() -> void:
	rig.play(rig.actions[0])

func _physics_process(delta: float) -> void:
	dealer.tick(delta)
	age += delta
	if life > 0.0 and age >= life:
		queue_free()
		return
	if mover.is_valid():
		mover.call(self, delta)
	elif velocity != Vector2.ZERO or accel != Vector2.ZERO:
		velocity += accel * delta
		var step := velocity * delta
		position += step
		if distance_left > 0.0:
			distance_left -= step.length()
			if distance_left <= 0.0:
				queue_free()
				return
	if not is_instance_valid(source):
		return
	dealer.scan(rig.hitbox, attack, _deliver, true)
	if dealer.spent(attack) and attack.max_hits <= 1:
		queue_free()

func _deliver(target: Actor) -> bool:
	var h := Hit.new()
	h.source = source
	h.attack = attack
	h.action = action
	if damage_fn.is_valid():
		h.damage = damage_fn.call()
	else:
		h.damage = source.outgoing_damage(attack)
		h.crit = source.last_crit
	h.origin = global_position
	h.carrier = self
	# moving bullets push along their flight, static effects push away from their centre
	if velocity.x != 0.0:
		h.direction = 1 if velocity.x > 0.0 else -1
	elif push_dir != 0:
		h.direction = push_dir
	else:
		var dx := target.global_position.x - global_position.x
		if absf(dx) < 2.0 and source is Actor:   # on the same spot (an effect placed on its target): the way the owner faces
			h.direction = (source as Actor).facing
		else:
			h.direction = 1 if dx >= 0.0 else -1
	var landed: bool = target.take_hit(h)
	if landed and on_hit.is_valid():
		on_hit.call(target)
	if landed and source is Monster and target is Hero:
		(source as Monster).brain.on_hit_hero(target, action)
	return landed

func _on_event(n: StringName, _args: Array) -> void:
	# an effect that ends itself: "finished" (its script removes the clip) or a call to destroy()
	if n == &"destroy" or n == &"finished" or (n == &"call" and not _args.is_empty() and _args[0] == "destroy"):
		queue_free()
	elif n == &"new_hit":
		_new_hits += 1
		if new_hit_limit < 0 or _new_hits <= new_hit_limit:
			dealer.new_serial()
	elif n == &"raw" and String(_args[0]).contains("shake"):
		Level.current.shake(25)
