class_name HitDealer
extends RefCounted
## Tracks who an attack already hit.
## Melee: each target is hit once per attack serial (new_serial() = the original newAttackId()).
## Projectiles: a target can be hit again after `rehit_interval`, until `max_hits` are spent.

var serial := 0
var hits := 0
var _log := {}    ## target instance id -> [serial, cooldown left]

func new_serial() -> void:
	serial += 1

func reset() -> void:
	serial += 1
	hits = 0
	_log.clear()

func tick(delta: float) -> void:
	for k in _log:
		_log[k][1] -= delta

## Test `rect` against every target's hurt rect and call `deliver(target) -> bool` for fresh overlaps.
func scan(rect: Rect2, targets: Array, attack: AttackData, deliver: Callable, projectile := false) -> void:
	if rect.size == Vector2.ZERO or attack == null:
		return
	for t in targets:
		if projectile and hits >= attack.max_hits:
			return
		if not is_instance_valid(t) or not t.can_be_hit():
			continue
		var id: int = t.get_instance_id()
		var entry = _log.get(id)
		# same serial: melee never re-hits; projectiles may after rehit_interval
		if entry != null and entry[0] == serial:
			if not projectile or attack.rehit_interval <= 0.0 or entry[1] > 0.0:
				continue
		if not rect.intersects(t.hurt_rect()):
			continue
		if deliver.call(t):
			_log[id] = [serial, attack.rehit_interval]
			hits += 1

func spent(attack: AttackData) -> bool:
	return attack != null and hits >= attack.max_hits
