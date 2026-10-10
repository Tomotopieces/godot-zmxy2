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

## The targets whose hurt box overlaps `hitbox` (an Area2D that only sees the other team's hurt layer) and that have not
## been hit yet by this attack: `deliver(target) -> bool` for each.
func scan(hitbox: Area2D, attack: AttackData, deliver: Callable, projectile := false) -> void:
	if attack == null or (hitbox.get_child(0) as CollisionShape2D).disabled:
		return
	for area in hitbox.get_overlapping_areas():
		if projectile and hits >= attack.max_hits:
			return
		var t = area.get_meta(&"actor", null)
		if t == null or not is_instance_valid(t) or not t.can_be_hit():
			continue
		var id: int = t.get_instance_id()
		var entry = _log.get(id)
		# same serial: melee never re-hits; projectiles may after rehit_interval
		if entry != null and entry[0] == serial:
			if not projectile or attack.rehit_interval <= 0.0 or entry[1] > 0.0:
				continue
		if deliver.call(t):
			_log[id] = [serial, attack.rehit_interval]
			hits += 1

func spent(attack: AttackData) -> bool:
	return attack != null and hits >= attack.max_hits
