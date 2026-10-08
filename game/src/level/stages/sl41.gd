extends StageScript
## 4-1 (StageListener41): when the final form appears, the two floating platforms move into the arena and drift
## sideways, wrapping around the screen.

var _moving: Array = []   ## [body, velocity, wrap]

func start_final_platforms() -> void:
	var fp: Dictionary = param("final_platforms", {})
	var floats := level.walls.filter(func(b): return b.get_meta(&"wall").kind == "oneway")
	floats.sort_custom(func(a, b): return a.position.x < b.position.x)
	var positions: Array = fp.get("positions", [])
	for i in mini(floats.size(), positions.size()):
		var b: AnimatableBody2D = floats[i]
		var v := float(fp.get("speed", 48)) * (1.0 if b.position.x < 1500.0 else -1.0)
		b.position = Vector2(positions[i][0], positions[i][1])
		if fp.has("art"):
			var art := Rig.create(String(fp.art))
			b.add_child(art)
			art.play(art.actions[0])
		_moving.append([b, Vector2(v, 0), float(fp.get("wrap", 1400))])

func _physics_process(delta: float) -> void:
	var view := level.view_rect()
	for mv in _moving:
		var b: AnimatableBody2D = mv[0]
		b.position += mv[1] * delta
		var half: float = ((b.get_child(0) as CollisionShape2D).shape as RectangleShape2D).size.x / 2.0
		if b.position.x < view.position.x - half:
			b.position.x += mv[2]
		elif b.position.x > view.end.x + half:
			b.position.x -= mv[2]
