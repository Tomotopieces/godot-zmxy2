class_name Orb
extends Node2D
## Soul orb dropped by monsters (BaseAura): waits, floats up, then homes in on the hero with growing speed.
## red = souls, green = HP, blue = MP, white = rage.

enum Kind { RED, GREEN, BLUE, WHITE }

const PUPPETS := {Kind.RED: "orb_Red", Kind.GREEN: "orb_Green", Kind.BLUE: "orb_Blue", Kind.WHITE: "orb_While"}

var kind := Kind.RED
var power := 0
var target: Hero
var table: DropTable
var _wait := 0.0
var _life := 0.0
var _speed := 0.0
var _homing := false

static func spawn(k: Kind, pos: Vector2, hero: Hero, value: int, t: DropTable) -> Orb:
	var o := Orb.new()
	o.kind = k
	o.position = pos
	o.target = hero
	o.power = value
	o.table = t
	var r := Puppet.create(PUPPETS[k])
	o.add_child(r)
	o.z_index = Layers.Z_PICKUP
	Level.current.add_object(o)
	r.play(r.actions[0])
	return o

func _ready() -> void:
	_wait = table.orb_delay
	_speed = Rng.randf_range(table.orb_speed.x, table.orb_speed.y)

func _physics_process(delta: float) -> void:
	_life += delta
	if _life > table.orb_life or not is_instance_valid(target) or not target.is_alive():
		queue_free()
		return
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			var tw := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			tw.tween_property(self, "position:y", position.y - Rng.randf_range(table.orb_rise.x, table.orb_rise.y), table.orb_rise_time)
			tw.tween_callback(func(): _homing = true)
		return
	if not _homing:
		return
	var to := target.global_position - global_position
	var step := _speed * delta
	if to.length() <= maxf(table.orb_pickup, step):
		_collect()
		return
	global_position += to.normalized() * step
	_speed = minf(_speed + table.orb_accel * delta, table.orb_max_speed)

func _collect() -> void:
	match kind:
		Kind.RED:
			GameState.add_souls(power)
		Kind.GREEN:
			target.heal(power, false)
		Kind.BLUE:
			target.restore_mp(power)
		Kind.WHITE:
			target.add_orb_rage(power)
	queue_free()
