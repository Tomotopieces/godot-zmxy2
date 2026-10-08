extends StageScript
## 3-1 (StageListener31): the boat ride. The boat sails right with a gentle bob; soldiers jump out of the water onto
## it and fish leap over it; when it reaches the far pier it stops and the exit opens. Once, an aurora drifts by:
## a hero carrying the 避水珠 (bsz) who touches it dives to 楚江王 (8-1).
## (Fix of the original: fish from both sides leap toward the boat; they all flew the same way.)

var _boat: AnimatableBody2D
var _bob: Array
var _bob_t := 0.0
var _bob_i := 0
var _bob_dir := 1
var _sailing := true
var _jump_t := 0.0
var _fish_t := 0.0
var _fish_on := false
var _emitter: Monster
var _aurora: Rig
var _aurora_life := 0.0

func setup() -> void:
	for b in level.walls:
		if b.get_meta(&"wall").cls == "export.Boat":
			_boat = b
	if _boat == null:
		return
	var art := Rig.create("boat")
	_boat.add_child(art)
	art.play(art.actions[0])
	_bob = param("boat", {}).get("bob", [])
	_jump_t = float(param("jumpers", {}).get("first", 8.0))
	var fish: Dictionary = param("fish", {})
	get_tree().create_timer(float(fish.get("start", 5.0)), false).timeout.connect(func():
		_fish_on = _sailing
		_fish_t = float(fish.get("first", 3.0)))
	var at: Array = param("aurora", {}).get("at", [5.0, 15.0])
	get_tree().create_timer(Rng.randf_range(at[0], at[1]), false).timeout.connect(_show_aurora)

func _physics_process(delta: float) -> void:
	if _boat == null:
		return
	if _sailing:
		_sail(delta)
		_jumpers(delta)
	if _fish_on:
		_fish(delta)
	_update_aurora(delta)

## x += speed; y follows the bob table down then up (ObsWall speedY).
func _sail(delta: float) -> void:
	var cfg: Dictionary = param("boat", {})
	_boat.position.x += float(cfg.get("speed", 48)) * delta
	_bob_t += delta
	var step := float(cfg.get("bob_step", 0.05))   # one table entry per original frame
	while _bob_t >= step and not _bob.is_empty():
		_bob_t -= step
		_boat.position.y += float(_bob[_bob_i]) * _bob_dir
		_bob_i += 1
		if _bob_i >= _bob.size():
			_bob_i = 0
			_bob_dir = -_bob_dir
	if _boat.position.x >= float(cfg.get("stop_x", 4129)):
		_sailing = false
		_fish_on = false
		level.open_door()

func _jumpers(delta: float) -> void:
	var cfg: Dictionary = param("jumpers", {})
	_jump_t -= delta
	if _jump_t > 0.0 or level.monsters().size() >= Layers.MAX_MONSTERS:
		return
	var r: Array = cfg.get("every", [3.0, 7.0])
	_jump_t = Rng.randf_range(r[0], r[1])
	var x := _boat.position.x + float(cfg.get("dx", 100)) * (1.0 if Rng.randf() < 0.5 else -1.0)
	var fx := place_rig("monster41_jump", Vector2(x, _boat.position.y + float(cfg.get("from_dy", 150))), Layers.Z_MONSTER)
	var tw := fx.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(fx, "position:y", _boat.position.y + float(cfg.get("to_dy", -60)), float(cfg.get("rise", 1.5)))
	tw.tween_callback(func():
		var md := level.monster_data(int(cfg.get("monster", 41)))
		if md and _sailing:
			var m := Monster.create(md)
			m.position = fx.position + Vector2(0, 10)
			level.add_monster(m)
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
	var half := ((_boat.get_child(0) as CollisionShape2D).shape as RectangleShape2D).size.x / 2.0
	var n: Array = cfg.get("count", [2, 4])
	for i in Rng.randi_range(n[0], n[1]):
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

func _show_aurora() -> void:
	var cfg: Dictionary = param("aurora", {})
	_aurora = Rig.create("aurora")
	_aurora.z_index = Layers.Z_MECHANISM
	# placed once at (1000, 600) of the scene (StageListener31: a screen point converted into the scene's
	# parent, which does not scroll) and left there
	var at: Array = cfg.get("pos", [1000, 600])
	_aurora.position = Vector2(at[0], at[1])
	level.add_object(_aurora)
	_aurora.play(_aurora.actions[0])
	_aurora_life = float(cfg.get("life", 15.0))

func _update_aurora(delta: float) -> void:
	if _aurora == null:
		return
	_aurora_life -= delta
	if _aurora_life <= 0.0:
		_aurora.queue_free()
		_aurora = null
		return
	var cfg: Dictionary = param("aurora", {})
	var r := _aurora.hit_rect()
	if r.size != Vector2.ZERO and hero_in(r) and GameState.take_item(String(cfg.get("key", "bsz"))):
		level.go_to(Vector2i(cfg.to[0], cfg.to[1]))
