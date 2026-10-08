class_name DamageNumber
extends Node2D
## Floating bitmap number (my/ANumber): digits from assets/ui/digits/<style><d>.png, rises then disappears.
## Styles: hurtnum (monster hit), bnum (crit), pnum (hero hurt), bunum (heal).

const RISE_SPEED := 75.0   ## px/s
const LIFE := 1.0          ## s

const MISS := preload("res://assets/ui/digits/miss.png")
static var _tex := {}
static var _pool: Array[DamageNumber] = []   ## finished numbers waiting to be reused (hits are frequent)

static func spawn(style: String, value: int, pos: Vector2, spacing := 20.0) -> void:
	var n: DamageNumber = _pool.pop_back() if not _pool.is_empty() else DamageNumber.new()
	var s := str(value)
	while n.get_child_count() < s.length():
		var sp := Sprite2D.new()
		sp.centered = false
		n.add_child(sp)
	for i in n.get_child_count():
		var sp := n.get_child(i) as Sprite2D
		sp.visible = i < s.length()
		if sp.visible:
			var key := style + s[i]
			if not _tex.has(key):
				_tex[key] = load("res://assets/ui/digits/%s.png" % key)
			sp.texture = _tex[key]
			sp.position.x = i * spacing
	n._t = 0.0
	n.position = pos
	n.z_index = Layers.Z_NUMBER
	n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved in _process
	Level.current.add_object(n)

static func spawn_miss(pos: Vector2) -> void:
	var sp := Sprite2D.new()
	sp.texture = MISS
	sp.position = pos
	sp.z_index = Layers.Z_NUMBER
	sp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Level.current.add_object(sp)
	var tw := sp.create_tween().set_parallel()
	tw.tween_property(sp, "position:y", pos.y - 60, 2.0)
	tw.tween_property(sp, "modulate:a", 0.0, 2.0)
	tw.chain().tween_callback(sp.queue_free)

var _t := 0.0

func _process(delta: float) -> void:
	position.y -= RISE_SPEED * delta
	_t += delta
	if _t > LIFE:
		_release()

func _release() -> void:
	if is_inside_tree():
		get_parent().remove_child(self)
	_pool.append(self)

## Frees the pooled numbers (stage end: they belong to no tree).
static func clear_pool() -> void:
	for n in _pool:
		n.free()
	_pool.clear()
