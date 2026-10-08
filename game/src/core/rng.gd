class_name Rng
extends RefCounted
## The one source of gameplay randomness (drops, AI rolls, damage spread). Tests call seed_with() for repeatable runs.

static var _r := RandomNumberGenerator.new()

static func seed_with(s: int) -> void:
	_r.seed = s

static func randf() -> float:
	return _r.randf()

static func randi() -> int:
	return _r.randi()

static func randf_range(a: float, b: float) -> float:
	return _r.randf_range(a, b)

static func randi_range(a: int, b: int) -> int:
	return _r.randi_range(a, b)
