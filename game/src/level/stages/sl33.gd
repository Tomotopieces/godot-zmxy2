extends StageScript
## 3-3 (StageListener33): five pearls along the way break after a few hits (each new attack counts once) and may
## drop the 避水珠 (bsz). When 孟婆 appears, a hidden wall shuts the player into her arena.

var _pearls: Array = []   ## [puppet, hp, last attack serial]

func setup() -> void:
	var cfg: Dictionary = param("pearls", {})
	for pos in cfg.get("positions", []):
		var pearl := place_puppet("pearl", Vector2(pos[0], pos[1]))
		pearl.hurtbox.collision_layer = Actor.LAYER_HURT_MONSTER   # the hero's attack box sees it
		_pearls.append([pearl, int(cfg.get("hp", 5)), -1])

func on_monster_added(m: Monster) -> void:
	if m.data.id == int(param("hidden_wall_boss", 47)):
		level.enable_hidden_walls()

func _physics_process(_delta: float) -> void:
	var h := level.hero
	if not is_instance_valid(h):
		return
	var cfg: Dictionary = param("pearls", {})
	for pr in _pearls:
		if pr[1] <= 0 or h.dealer.serial == pr[2]:
			continue
		var r: Puppet = pr[0]
		if not h.hits(r.hurtbox):
			continue
		pr[2] = h.dealer.serial
		pr[1] -= 1
		Fx.spawn("fx_monster_hurt1" if Rng.randf() < 0.5 else "fx_monster_hurt2", r.hurtbox.global_position)
		if pr[1] <= 0:
			if Rng.randf() < float(cfg.get("drop_chance", 0.2)):
				GroundItem.spawn(String(cfg.get("drop", "bsz")), r.position)
			var tw := r.create_tween()
			tw.tween_property(r, "modulate:a", 0.0, float(cfg.get("fade", 1.0)))
			tw.tween_callback(r.queue_free)
