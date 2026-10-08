class_name Actor
extends CharacterBody2D
## Shared base of Hero and Monster: rig, facing, HP, hit scanning.
## Rig art faces left, so facing right mirrors the rig.

signal died(actor: Actor)

const LAYER_WORLD := 1
const LAYER_ONEWAY := 2
const LAYER_HERO := 4
const LAYER_MONSTER := 8

## The stage this actor lives in (one place that reads the Level.current locator; everything else asks the actor).
var world: Level:
	get:
		return Level.current

var rig: Rig
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

func setup_rig(rig_name: String) -> void:
	rig = Rig.create(rig_name)
	add_child(rig)
	rig.scale.x = -facing
	rig.event.connect(_on_rig_event)
	rig.action_finished.connect(_on_action_finished)
	rig.play(&"wait" if rig.actions.has("wait") else StringName(rig.actions[0]))
	# body = hurt box of the idle pose
	var cs := rig.hurtbox.get_child(0) as CollisionShape2D
	var body := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = cs.shape.size
	body.shape = shape
	body.position = Vector2(cs.position.x * rig.scale.x, cs.position.y)
	add_child(body)

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

func scan_hits(targets: Array) -> void:
	if attack and attack.projectile == "":
		dealer.scan(rig.hit_rect(), targets, attack, _deliver)

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
	return landed

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
