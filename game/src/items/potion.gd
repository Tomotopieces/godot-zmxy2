class_name Potion
extends CharacterBody2D
## HP / MP potion dropped by monsters (export.cure): falls to the floor, heals on touch, expires.

enum Kind { SMALL_HP, BIG_HP, SMALL_MP }

const RIGS := {Kind.SMALL_HP: "potion_SmallHP", Kind.BIG_HP: "potion_BigHP", Kind.SMALL_MP: "potion_SmallMP"}

var kind := Kind.SMALL_HP
var amount := 0
var table: DropTable
var rig: Rig
var _life := 0.0
var _used := false

static func spawn(k: Kind, pos: Vector2, t: DropTable) -> Potion:
	var p := Potion.new()
	p.kind = k
	p.table = t
	p.amount = {Kind.SMALL_HP: t.small_hp, Kind.BIG_HP: t.big_hp, Kind.SMALL_MP: t.small_mp}[k]
	p.rig = Rig.create(RIGS[k])
	p.add_child(p.rig)
	var cs := p.rig.get_node("Hurtbox/Shape") as CollisionShape2D
	var body := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = cs.shape.size
	body.shape = shape
	body.position = cs.position
	p.add_child(body)
	p.collision_layer = 0
	p.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ONEWAY
	p.position = pos - Vector2(0, shape.size.y)
	p.z_index = Layers.Z_PICKUP
	Level.current.add_object(p)
	p.rig.play(p.rig.actions[0])
	return p

func _physics_process(delta: float) -> void:
	if _used:
		return
	_life += delta
	if _life > table.potion_life or global_position.y > Hero.FALL_DEATH_Y:
		queue_free()
		return
	velocity.y += GameState.hero_data.gravity * delta
	move_and_slide()
	var h: Hero = Level.current.hero
	if is_instance_valid(h) and h.is_alive() and rig.hurt_rect().intersects(h.hurt_rect()):
		_use(h)

func _use(h: Hero) -> void:
	_used = true
	if kind == Kind.SMALL_MP:
		h.restore_mp(amount)
		DamageNumber.spawn("bulnum", amount, h.global_position + Vector2(-20, -60))
	else:
		h.heal(amount)
	var tw := create_tween().set_parallel().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(self, "position:y", position.y - 100, 0.8)
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(queue_free)
