class_name TangShadow
extends CharacterBody2D
## 唐僧's 分身 (Role2Shadow): walks on in the direction he faced for a while, can't be hurt. The hero's U / O skills
## are cast again from where it stands (冰柱 / 群体回血), then it disappears; pressing I again swaps places with it.

var hero: Hero
var rig: Rig
var facing := 1
var life := 0.0
var speed := 0.0
var _busy := false

static func create(h: Hero) -> TangShadow:
	var s := TangShadow.new()
	s.hero = h
	s.facing = h.facing
	var k: Dictionary = h.data.kit.shadow
	s.life = float(k.life)
	s.speed = float(k.speed)
	s.global_position = h.global_position
	return s

func _ready() -> void:
	collision_layer = 0
	collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ONEWAY
	z_index = Layers.Z_HERO - 1
	add_child(hero.body_shape.duplicate())
	rig = Rig.create("tangseng_shadow")
	rig.scale.x = -facing
	add_child(rig)
	rig.event.connect(_on_event)
	rig.play(&"walk")

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0 and not _busy:
		queue_free()
		return
	velocity.x = 0.0 if _busy else facing * speed
	velocity.y += hero.data.gravity * delta
	move_and_slide()

func _exit_tree() -> void:
	if is_instance_valid(hero) and hero.get("_shadow") == self:
		hero.set("_shadow", null)

## U: casts 冰柱 from here.
func do_hit3() -> void:
	_busy = true
	rig.play(&"hit3")

## O: heals the heroes near it when its animation ends.
func do_hit5() -> void:
	_busy = true
	rig.play(&"hit5")
	Snd.sfx("Role2_hit5")

func _on_event(n: StringName, args: Array) -> void:
	if n != &"call" or not is_instance_valid(hero):
		return
	match args[0]:
		"special_attack":
			hero.call("_spawn_ice", global_position, self)
		"cure_role":
			var c: Dictionary = hero.data.kit.cure
			var d := hero.global_position - global_position
			if absf(d.x) <= float(c.range) and absf(d.y) <= float(c.range) * 0.8 and hero.is_alive():
				hero.heal(hero.call("_cure_amount", false))
		"destroy":
			queue_free()
