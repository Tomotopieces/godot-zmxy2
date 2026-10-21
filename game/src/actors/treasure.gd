class_name Treasure
extends Node2D
## Worn magic treasure (BaseMagicWeapon): floats behind the hero and is used with H for MP (30 + 10 x level).
## It can be used in any state; while its skill runs (`using`) it cannot be used again (no other cooldown).
## Each treasure is a subclass in src/actors/treasures/treasure_<id>.gd; numbers in HeroData.treasures.

const DIR := "res://src/actors/treasures/"

var hero: Hero
var item: Item             ## the worn item (lv, growth, elem ...)
var id := ""
var p: Dictionary          ## this treasure's numbers
var world: Level:
	get:
		return Level.current
var puppet: Puppet
var using := false
var facing := -1:
	set(v):
		facing = 1 if v >= 0 else -1
		if puppet:
			puppet.scale.x = -facing

var _move: Tween

static func create(h: Hero, it: Item) -> Treasure:
	var path := DIR + "treasure_%s.gd" % it.id
	var t: Treasure = load(path).new() if ResourceLoader.exists(path) else Treasure.new()
	t.hero = h
	t.item = it
	t.id = it.id
	t.p = h.data.treasures.get(t.id, {})
	return t

func _ready() -> void:
	z_index = Layers.Z_TREASURE
	puppet = Puppet.create("fabao_" + id)
	add_child(puppet)
	puppet.event.connect(_on_puppet_event)
	puppet.action_finished.connect(_on_action_finished)
	puppet.play(&"walk")
	facing = hero.facing
	global_position = home()
	reset_physics_interpolation()
	_follow()
	Timers.start(self, hero.data.treasures.follow, _follow, true)   # it catches up with the hero at this cadence
	setup()

func level() -> int:
	return item.lv

func wood() -> bool:
	return Forge.has_element(item, "mu")

## Random multiplier range: the wood range for 木 treasures, else `normal` (a [min, max] key of p, or none).
func mul_range(normal := "") -> Array:
	return p.get("wood_mul", [1.0, 1.0]) if wood() else p.get(normal, [1.0, 1.0])

func element_mul(normal := "") -> float:
	var r := mul_range(normal)
	return Rng.randf_range(r[0], r[1])

## Damage roll base + per_level x level +- spread / 2, times the element range. Built from plain values so the
## effects keep working after the treasure is taken off.
func flat_roll(base: float, per_level: float, spread: float, normal := "") -> Callable:
	var v := base + per_level * level()
	var r := mul_range(normal)
	return func() -> int: return int((v + (Rng.randf() - 0.5) * spread) * Rng.randf_range(r[0], r[1]))

## Damage roll k x hero attack, times the element range.
func power_roll(k: float, normal := "") -> Callable:
	var r := mul_range(normal)
	return func() -> int: return int(k * GameState.attack_power() * Rng.randf_range(r[0], r[1]))

## Resting place: behind the hero (setPosition).
func home() -> Vector2:
	var off: Array = hero.data.treasures.follow_offset
	return hero.global_position + Vector2(off[0] * hero.facing, off[1])

func _physics_process(delta: float) -> void:
	if not is_instance_valid(hero):
		queue_free()
		return
	step(delta)

func _follow() -> void:
	if is_instance_valid(hero) and follows():
		facing = hero.facing
		move_to(home(), hero.data.treasures.follow_tween)

func move_to(pos: Vector2, seconds: float, done := Callable()) -> void:
	if _move:
		_move.kill()
	_move = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_move.tween_property(self, "global_position", pos, seconds)
	if done.is_valid():
		_move.tween_callback(done)

## H: pay the MP and start the skill.
func use() -> void:
	if using or not hero.is_alive() or not can_use():
		return
	var cost := Forge.skill_cost(item)
	if hero.mp < cost:
		return
	hero.mp -= cost
	using = true
	if _move:
		_move.kill()
	begin()

func finish() -> void:
	using = false
	puppet.play(&"walk")

## Damage effect owned by the hero; the treasure's own damage roll replaces the hero's attack.
func shoot(puppet_name: String, attack_key: StringName, pos: Vector2, face: int, damage: Callable) -> Projectile:
	var pr := Projectile.create(puppet_name, hero, hero.data.attacks[attack_key], attack_key)
	pr.position = pos
	pr.facing = face
	pr.damage_fn = damage
	world.add_object(pr)
	return pr

## Everything a treasure may go for: monsters and hittable scene props (the 10-1 stones: 血海魔童 helps to open the
## doors that way; the original keeps them in the monster list too).
func targets() -> Array:
	return world.monsters() + get_tree().get_nodes_in_group(&"props")

## Targets that can be hit now and are not in the skip list.
func candidates(skip_key := "skip_monsters") -> Array:
	var skip: Array = p.get(skip_key, [])
	return targets().filter(func(m): return m.can_be_hit() and not (m.data.id in skip))

# ------------------------------------------------------------------ hooks

func setup() -> void:
	pass

## Whether it drifts back behind the hero (most stay put while their skill runs).
func follows() -> bool:
	return not using

func can_use() -> bool:
	return true

func begin() -> void:
	finish()

func step(_delta: float) -> void:
	pass

func _on_puppet_event(n: StringName, args: Array) -> void:
	if n == &"call":
		on_call(String(args[0]))

func on_call(_method: String) -> void:
	pass

func _on_action_finished(_a: StringName) -> void:
	pass
