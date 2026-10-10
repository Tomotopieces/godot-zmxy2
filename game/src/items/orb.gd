class_name Orb
extends Node2D
## Soul orb dropped by monsters: bursts out in a random direction, stops within 0.2 s, then flies at the hero accelerating like a stab.
## red = souls, green = HP, blue = MP, white = rage.

enum Kind { RED, GREEN, BLUE, WHITE }

const RIGS := {Kind.RED: "orb_Red", Kind.GREEN: "orb_Green", Kind.BLUE: "orb_Blue", Kind.WHITE: "orb_While"}

const BURST_SPEED := 260.0      ## px/s: the speed an orb leaves the monster with, in its own random direction ...
const BURST_TIME := 0.2         ## ... falling to zero over this long (so it travels about 26 px)
## Then it flies at the hero like the 八戒 stab: v = SEEK_START + SEEK_QUAD * max(t - SEEK_DELAY, 0)^2 (the stab's own
## numbers: a slow crawl first, then more and more speed)
const SEEK_START := 24.0        ## px/s
const SEEK_QUAD := 345.6        ## px/s^3
const SEEK_DELAY := 0.4167      ## s

var kind := Kind.RED
var power := 0
var target: Hero
var table: DropTable
var _life := 0.0
var _age := 0.0
var _dir := Vector2.RIGHT

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
	_dir = Vector2.from_angle(Rng.randf() * TAU)

func _physics_process(delta: float) -> void:
	_life += delta
	if _life > table.orb_life or not is_instance_valid(target) or not target.is_alive():
		queue_free()
		return
	_age += delta
	if _age < BURST_TIME:
		# the burst: along its random heading, slowing linearly to a stop
		global_position += _dir * BURST_SPEED * (1.0 - _age / BURST_TIME) * delta
		return
	var t := _age - BURST_TIME
	var to := target.global_position - global_position
	var step: float = (SEEK_START + SEEK_QUAD * pow(maxf(t - SEEK_DELAY, 0.0), 2.0)) * delta
	if to.length() <= maxf(table.orb_pickup, step):
		_collect()
		return
	global_position += to.normalized() * step

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
