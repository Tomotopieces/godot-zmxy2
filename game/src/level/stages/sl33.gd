extends StageScript
## 3-3 (StageListener33): five pearls along the way break after a few hits (each new attack counts once) and may
## drop the 避水珠 (bsz). When 孟婆 appears, a hidden wall shuts the player into her arena.


var pearls: Array[HitTarget] = []   ## one per pearl; meta "hp" = hits left

func setup() -> void:
	var cfg: Dictionary = param("pearls", {})
	for pos in cfg.get("positions", []):
		var pearl := place_puppet("pearl", Vector2(pos[0], pos[1]))
		var target := HitTarget.attach(pearl.hurtbox)   # swings and bullets hit it like a monster, once per attack round
		target.set_meta(&"hp", int(cfg.get("hp", 5)))
		target.hit.connect(_on_pearl_hit.bind(pearl, target))
		pearls.append(target)

func on_monster_added(m: Monster) -> void:
	if m.data.id == int(param("hidden_wall_boss", 47)):
		level.enable_hidden_walls()

func _on_pearl_hit(_h: Hit, pearl: Puppet, target: HitTarget) -> void:
	var hp: int = target.get_meta(&"hp") - 1
	target.set_meta(&"hp", hp)
	if hp > 0:
		return
	target.enabled = false
	var cfg: Dictionary = param("pearls", {})
	if Rng.randf() < float(cfg.get("drop_chance", 0.2)):
		GroundItem.spawn(String(cfg.get("drop", "bsz")), pearl.position)
	var tw := pearl.create_tween()
	tw.tween_property(pearl, "modulate:a", 0.0, float(cfg.get("fade", 1.0)))
	tw.tween_callback(pearl.queue_free)
