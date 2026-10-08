class_name GroundItem
extends CharacterBody2D
## Dropped equipment (my/FallEquipObj): falls to the floor and goes into the bag on touch.
## Expires after a while unless it is boss loot; stays on the ground while the bag is full.

var item: Dictionary
var _life := 0.0
var _keep := false
var _taken := false
var _sprite: Sprite2D

static func spawn(id: String, pos: Vector2) -> GroundItem:
	var d := EquipmentCatalog.find(id)
	if d == null:
		return null
	var g := GroundItem.new()
	g.item = d.roll()
	g._keep = EquipmentCatalog.get_catalog().boss_loot.has(id)
	g._sprite = Sprite2D.new()
	g._sprite.texture = d.ground_icon
	g.add_child(g._sprite)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = d.ground_icon.get_size() if d.ground_icon else Vector2(40, 40)
	cs.shape = shape
	g.add_child(cs)
	g.collision_layer = 0
	g.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ONEWAY
	g.position = pos
	g.z_index = Layers.Z_PICKUP
	Level.current.add_object(g)
	return g

func _rect() -> Rect2:
	var s := (get_child(1) as CollisionShape2D).shape.size as Vector2
	return Rect2(global_position - s / 2.0, s)

func _physics_process(delta: float) -> void:
	if _taken:
		return
	_life += delta
	if (_life > EquipmentCatalog.get_catalog().ground_life and not _keep) or global_position.y > Hero.FALL_DEATH_Y:
		queue_free()
		return
	velocity.y += GameState.hero_data.gravity * delta
	move_and_slide()
	var h: Hero = Level.current.hero
	if is_instance_valid(h) and h.is_alive() and _rect().intersects(h.hurt_rect()) and GameState.add_to_bag(item):
		_taken = true
		var tw := create_tween().set_parallel().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(self, "position:y", position.y - 100, 0.8)
		tw.tween_property(self, "modulate:a", 0.0, 0.8)
		tw.chain().tween_callback(queue_free)
