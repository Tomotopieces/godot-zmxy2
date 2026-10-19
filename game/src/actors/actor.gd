class_name Actor
extends CharacterBody2D
## Shared base of Hero and Monster: rig, facing, HP, hit scanning.
## Rig art faces left, so facing right mirrors the rig.

signal died(actor: Actor)

const LAYER_WORLD := 1
const LAYER_ONEWAY := 2
const LAYER_HERO := 4
const LAYER_MONSTER := 8
const LAYER_HURT_HERO := 16      ## hurt boxes (Area2D): what monsters' attacks overlap
const LAYER_HURT_MONSTER := 32   ## what the heroes' attacks overlap

## The stage this actor lives in (one place that reads the Level.current locator; everything else asks the actor).
var world: Level:
	get:
		return Level.current

func _init() -> void:
	# Wall.setYByRole: on a slope the original moves at the walking speed along the slope (x cos, y sin)
	floor_constant_speed = true
	floor_snap_length = 8.0

var rig: Rig
var body_shape: CollisionShape2D   ## the actor's body collider (sized from the idle hurt box)
var hp := 1
var max_hp := 1
var gravity := 0.0
var dealer := HitDealer.new()
var attack: AttackData         ## attack of the action being played (null when not attacking)
var attack_action: StringName
var last_crit := false        ## set by outgoing_damage()
var facing := -1:
	set(v):
		facing = 1 if v >= 0 else -1
		if rig:
			rig.scale.x = -facing

## The actor's art: its hand-edited scene scenes/actors/<name>/<name>.tscn (README "Actor scenes").
func setup_rig(rig_name: String) -> void:
	rig = Rig.create(rig_name)
	add_child(rig)
	rig.scale.x = -facing
	rig.event.connect(_on_rig_event)
	# attacks find their targets by physics overlap: this body's hurt box is on its team's hurt layer, its hit box looks at the other
	var hero := self is Hero
	rig.hurtbox.collision_layer = LAYER_HURT_HERO if hero else LAYER_HURT_MONSTER
	rig.hurtbox.set_meta(&"actor", self)
	rig.hitbox.collision_mask = LAYER_HURT_MONSTER if hero else LAYER_HURT_HERO
	rig.action_finished.connect(_on_action_finished)
	rig.play(&"wait" if rig.actions.has("wait") else StringName(rig.actions[0]))
	# body = hurt box of the idle pose
	var cs := rig.hurtbox.get_child(0) as CollisionShape2D
	var body := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = cs.shape.get_rect().size   # (whatever shape the hurt box was given in the scene)
	body.shape = shape
	body.position = Vector2(cs.position.x * rig.scale.x, cs.position.y)
	add_child(body)
	body_shape = body

## Hit-stop (Level.hit_stop): the actor's logic and animation hold still for a moment.
var stop_t := 0.0

func hit_stop(seconds: float) -> void:
	stop_t = maxf(stop_t, seconds)
	rig.anim.speed_scale = 0.0

## Counts the hit-stop down; true while the actor is held (its _physics_process does nothing else).
func tick_stop(delta: float) -> bool:
	if stop_t <= 0.0:
		return false
	stop_t -= delta
	if stop_t <= 0.0:
		rig.anim.speed_scale = 1.0
	return true

func is_alive() -> bool:
	return hp > 0

func can_be_hit() -> bool:
	return is_alive()

func hurt_rect() -> Rect2:
	return rig.hurt_rect()

func center() -> Vector2:
	var r := hurt_rect()
	return r.get_center() if r.size != Vector2.ZERO else global_position

## Start an attack action: fresh hit log, plays the rig action.
func start_attack(action: StringName, data: AttackData) -> void:
	attack = data
	attack_action = action
	dealer.reset()
	rig.play(action, true)

func end_attack() -> void:
	attack = null
	attack_action = &""

func scan_hits() -> void:
	if attack and attack.projectile == "":
		dealer.scan(rig.hitbox, attack, _deliver)

func _deliver(target: Actor) -> bool:
	var h := Hit.new()
	h.source = self
	h.attack = attack
	h.action = attack_action
	h.damage = outgoing_damage(attack)
	h.crit = last_crit
	h.origin = rig.hit_rect().get_center()
	h.direction = facing
	if attack.push_from_center:
		h.direction = 1 if target.global_position.x >= h.origin.x else -1
	var landed: bool = target.take_hit(h)
	if landed and self is Monster and target is Hero:
		(self as Monster).brain.on_hit_hero(target, attack_action)
	if landed:
		if self is Hero:
			(self as Hero).feel_hit(target, attack, h.crit, dealer, true)
		_on_landed(target)
	return landed

## A melee hit of this actor landed on `target` (virtual).
func _on_landed(_target: Actor) -> void:
	pass

## Spawn the attack's projectile (monster bullets) in front of the actor.
func fire_projectile(data: AttackData, action: StringName) -> Projectile:
	var p := Projectile.create(data.projectile, self, data, action)
	p.position = global_position + Vector2(data.spawn_offset.x * facing, data.spawn_offset.y)
	p.facing = facing
	p.velocity = Vector2(data.speed * facing, 0)
	p.distance_left = data.distance
	world.add_object(p)
	if data.spin_deg != 0.0:
		p.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).tween_property(p.rig, "rotation_degrees", data.spin_deg * -facing, data.spin_time)
	return p

func apply_gravity(delta: float) -> void:
	velocity.y += gravity * delta

## Damage this actor's attack deals before the target's defense.
func outgoing_damage(_a: AttackData) -> int:
	return 1

## Returns true when the hit landed.
func take_hit(_h: Hit) -> bool:
	return false

func _on_rig_event(_name: StringName, _args: Array) -> void:
	pass

func _on_action_finished(_action: StringName) -> void:
	pass
