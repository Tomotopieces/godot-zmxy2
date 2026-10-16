extends StageScript
## 3-1 (StageListener31): the boat ride. The boat (scenes/objects/boat.tscn, Objects/Boat of the stage scene) sails by itself;
## soldiers jump out of the water onto it and fish leap over it; when it reaches the far pier the exit opens. An aurora
## (scenes/objects/aurora_gate.tscn, Objects/AuroraGate) hangs over the water: a hero carrying the 避水珠 (bsz) who touches
## it dives to 楚江王 (8-1).
## (Fix of the original: fish from both sides leap toward the boat; they all flew the same way.)

var _boat: Boat
var _jump_t := 0.0
var _fish_t := 0.0
var _fish_on := false
var _emitter: Monster

func setup() -> void:
	_boat = level.world.get_node_or_null("Objects/Boat") as Boat
	if _boat == null:
		return
	_boat.arrived.connect(func():
		_fish_on = false
		level.open_door())
	_jump_t = float(param("jumpers", {}).get("first", 8.0))
	var fish: Dictionary = param("fish", {})
	get_tree().create_timer(float(fish.get("start", 5.0)), false).timeout.connect(func():
		_fish_on = _boat.sailing
		_fish_t = float(fish.get("first", 3.0)))

func _physics_process(delta: float) -> void:
	if _boat == null:
		return
	if _boat.sailing:
		_jumpers(delta)
	if _fish_on:
		_fish(delta)

func _jumpers(delta: float) -> void:
	var cfg: Dictionary = param("jumpers", {})
	_jump_t -= delta
	if _jump_t > 0.0 or level.monsters().size() >= Layers.MAX_MONSTERS:
		return
	var r: Array = cfg.get("every", [3.0, 7.0])
	_jump_t = Rng.randf_range(r[0], r[1])
	var x := _boat.position.x + float(cfg.get("dx", 100)) * Rng.randf_range(-1.0, 1.0)
	var fx := place_rig("monster41_jump", Vector2(x, _boat.position.y + float(cfg.get("from_dy", 150))), Layers.Z_EFFECT)
	var tw := fx.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(fx, "position:y", _boat.position.y + float(cfg.get("to_dy", -60)), float(cfg.get("rise", 1.5)))
	tw.tween_callback(func():
		var md := level.monster_data(int(cfg.get("monster", 41)))
		if md and _boat.sailing:
			var m := Monster.create(md)
			m.position = fx.position + Vector2(0, 10)
			level.add_monster(m)
			# feet just above the deck: the deck is a one-way platform, a body that starts inside it drops through
			var shape := _boat.get_node("Shape") as CollisionShape2D
			var deck := _boat.global_position.y + shape.position.y - (shape.shape as RectangleShape2D).size.y / 2.0
			var feet_off := m.body_shape.position.y + (m.body_shape.shape as RectangleShape2D).size.y / 2.0
			m.global_position.y = minf(m.global_position.y, deck - feet_off - 2.0)
			m.reset_physics_interpolation()
		fx.queue_free())

func _fish(delta: float) -> void:
	var cfg: Dictionary = param("fish", {})
	_fish_t -= delta
	if _fish_t > 0.0:
		return
	var r: Array = cfg.get("every", [1.0, 4.0])
	_fish_t = Rng.randf_range(r[0], r[1])
	if _emitter == null:
		# the invisible fish thrower (Monster57): owns the fish's attack, takes no part in the fight
		var md := level.monster_data(57)
		if md == null:
			return
		_emitter = Monster.create(md)
		_emitter.position = Vector2(-500, -500)
		_emitter.visible = false
		_emitter.invuln = INF
		level.add_object(_emitter)
	var half := _boat.half_width()
	var n: Array = cfg.get("count", [2, 4])
	# Monster57 re-rolls its loop condition `i < int(2 + random * 3)` every round: 2, 3 or 4 fish with chance 1/3, 4/9, 2/9
	var fish: int = int(n[0])
	while fish < int(n[1]) and Rng.randi() % 3 < (2 if fish == int(n[0]) else 1):
		fish += 1
	for i in fish:
		var side := 1.0 if Rng.randf() < 0.5 else -1.0
		var pos := Vector2(_boat.position.x + side * half + Rng.randf_range(-1, 1) * float(cfg.get("spread", 50)),
			_boat.position.y + Rng.randf() * float(cfg.get("depth", 50)))
		var speeds: Array = cfg.get("speeds", [[240, -480]])
		var odds: Array = cfg.get("speed_odds", [1.0])
		var roll := Rng.randf()
		var pick: Array = speeds[speeds.size() - 1]
		for k in odds.size():
			roll -= float(odds[k])
			if roll < 0.0:
				pick = speeds[k]
				break
		var f := _emitter.shoot("monster57bullet1", &"fish")
		f.global_position = pos
		f.velocity = Vector2(-side * float(pick[0]), float(pick[1]))
		f.accel = Vector2(0, float(cfg.get("gravity", 1152)))
		f.distance_left = 2000.0
