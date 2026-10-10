class_name Orb
extends Node2D
## Soul orb dropped by monsters: bursts out at a fixed speed in a random direction, then accelerates slowly toward the hero.
## red = souls, green = HP, blue = MP, white = rage.

enum Kind { RED, GREEN, BLUE, WHITE }

const RIGS := {Kind.RED: "orb_Red", Kind.GREEN: "orb_Green", Kind.BLUE: "orb_Blue", Kind.WHITE: "orb_While"}

const BURST_SPEED := 130.0      ## px/s: every orb leaves the monster at this speed, in its own random direction
const SEEK_ACCEL := 140.0       ## px/s^2 toward the hero when the burst ends ...
const SEEK_JERK := 520.0        ## ... growing by this much every second: a slow start that speeds up
const SEEK_MAX := 620.0         ## px/s
const SIDE_DAMPING := 2.6       ## per second: the sideways part of its speed fades, so the swing-in settles on the hero

var kind := Kind.RED
var power := 0
var target: Hero
var table: DropTable
var _life := 0.0
var _burst_left := 0.0
var _seek_time := 0.0
var _velocity := Vector2.ZERO

static func spawn(k: Kind, pos: Vector2, hero: Hero, value: int, t: DropTable) -> Orb:
	var o := Orb.new()
	o.kind = k
	o.position = pos
	o.target = hero
	o.power = value
	o.table = t
	var r := Rig.create(RIGS[k])
	o.add_child(r)
	o.z_index = Layers.Z_PICKUP
	Level.current.add_object(o)
	r.play(r.actions[0])
	return o

func _ready() -> void:
	_burst_left = table.orb_delay
	_velocity = Vector2.from_angle(Rng.randf() * TAU) * BURST_SPEED

func _physics_process(delta: float) -> void:
	_life += delta
	if _life > table.orb_life or not is_instance_valid(target) or not target.is_alive():
		queue_free()
		return
	if _burst_left > 0.0:
		# the burst: a fixed speed along its random heading
		_burst_left -= delta
		global_position += _velocity * delta
		return
	var to := target.global_position - global_position
	var dir := to.normalized()
	# slowly gathering speed toward the hero; what is left of the burst's heading swings round and fades
	_seek_time += delta
	var along := _velocity.dot(dir)
	var side := _velocity - dir * along
	side *= exp(-SIDE_DAMPING * delta)
	along = minf(along + (SEEK_ACCEL + SEEK_JERK * _seek_time) * delta, SEEK_MAX)
	_velocity = dir * along + side
	var step := _velocity * delta
	if to.length() <= maxf(table.orb_pickup, step.length()):
		_collect()
		return
	global_position += step

func _collect() -> void:
	match kind:
		Kind.RED:
			GameState.add_souls(power)
		Kind.GREEN:
			target.heal(power, false)
		Kind.BLUE:
			target.restore_mp(power)
		Kind.WHITE:
			target.add_rage(power)
	queue_free()
