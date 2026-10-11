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

## A value of the lo..hi range in steps of `step`, every step equally likely (the original's round(rand * k) gave the first
## and last step half the chance of the others).
static func stepped(lo: float, hi: float, step: float) -> float:
	return float(_r.randi_range(roundi(lo / step), roundi(hi / step))) * step

static func pick(a: Array) -> Variant:
	return a[_r.randi() % a.size()]
