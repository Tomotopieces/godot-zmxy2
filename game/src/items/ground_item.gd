class_name GroundItem
extends CharacterBody2D
## Dropped equipment (my/FallEquipObj): falls to the floor and goes into the bag on touch.
## Expires after a while unless it is boss loot; stays on the ground while the bag is full.

var item: Item
var _life := 0.0
var _keep := false
var _taken := false

signal expired   ## vanished without being picked up (AgentBridge reports it)
signal blocked(reason: String)   ## the hero touched it but could not take it (once per touch; AgentBridge reports it)
var _blocked := false

## Seconds before it vanishes; -1 for boss loot, which stays.
func expires_in() -> float:
	return -1.0 if _keep else maxf(0.0, EquipmentCatalog.get_catalog().ground_life - _life)
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
	shape.size = d.ground_size
	cs.shape = shape
	g.add_child(cs)
	var pick := Area2D.new()   # the hero picks it up when his hurt box overlaps this
	pick.name = "Pickup"
	pick.collision_layer = 0
	pick.collision_mask = Actor.LAYER_HURT_HERO
	var ps := CollisionShape2D.new()
	ps.shape = shape
	pick.add_child(ps)
	g.add_child(pick)
	g.collision_layer = 0
	g.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ONEWAY
	g.position = pos
	g.z_index = Layers.Z_PICKUP
	Level.current.add_object(g)
	return g

func _physics_process(delta: float) -> void:
	if _taken:
		return
	_life += delta
	if (_life > EquipmentCatalog.get_catalog().ground_life and not _keep) or global_position.y > Hero.FALL_DEATH_Y:
		expired.emit()
		queue_free()
		return
	velocity.y += GameState.hero_data.gravity * delta
	move_and_slide()
	var h: Hero = Level.current.hero
	var touching := is_instance_valid(h) and h.touches($Pickup)
	if touching and not GameState.can_add(item):
		if not _blocked:
			_blocked = true
			blocked.emit(GameState.why_cannot_add(item))
		return
	_blocked = false
	if touching and GameState.add_to_bag(item):
		_taken = true
		var tw := create_tween().set_parallel().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(self, "position:y", position.y - 100, 0.8)
		tw.tween_property(self, "modulate:a", 0.0, 0.8)
		tw.chain().tween_callback(queue_free)
