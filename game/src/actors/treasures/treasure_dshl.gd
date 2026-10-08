extends Treasure
## 地煞葫芦 (Cucurbit): 烈火咒, a fire in front of the gourd, each enemy hit once.

func follows() -> bool:
	return true

func begin() -> void:
	rig.play(&"hit1", true)

func on_call(method: String) -> void:
	match method:
		"create_fire":
			facing = hero.facing
			shoot("fabao_cucurbit_fire", &"fabao_cucurbit", global_position, facing,
				flat_roll(p.fire_damage, p.fire_per_level, p.fire_spread))
		"hit1_over":
			finish()
