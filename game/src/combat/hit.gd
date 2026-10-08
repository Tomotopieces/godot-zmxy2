class_name Hit
extends RefCounted
## One resolved hit, passed to Actor.take_hit().

var source: Node2D          ## the actor that owns the attack (hero / monster)
var attack: AttackData
var action: StringName
var damage := 0             ## before the target's defense
var crit := false
var origin := Vector2.ZERO  ## world position the hit came from (bullet / effect centre)
var direction := 1          ## knockback x direction (+1 = to the right)

## Damage after the target's defense (BaseMonster.getRealHurt / BaseHero.beAttack).
func mitigated(def: int, mdef: float) -> int:
	match attack.kind:
		AttackData.Kind.PHYSICS:
			return damage - def if damage > def else 1
		AttackData.Kind.MAGIC:
			return maxi(1, int(damage * (1.0 - mdef)))
	return maxi(1, damage)
