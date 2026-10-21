class_name HitTarget
extends Node2D
## Something that is not a monster but takes the hero's hits like one (a 3-3 pearl, the white-bone door's weak spot):
## attached to an Area2D, it puts that area on the monsters' hurt layer, so the hero's swings and bullets find it
## through the same physics overlap and hit rules as any monster. Each landed hit emits `hit`.

signal hit(h: Hit)

var enabled := true

static func attach(area: Area2D) -> HitTarget:
	var t := HitTarget.new()
	area.add_child(t)
	area.collision_layer = Actor.LAYER_HURT_MONSTER
	area.monitorable = true
	area.set_meta(&"actor", t)
	return t

func can_be_hit() -> bool:
	return enabled and is_visible_in_tree()

func take_hit(h: Hit) -> bool:
	if not can_be_hit():
		return false
	Fx.spawn("fx_monster_hurt1" if Rng.randf() < 0.5 else "fx_monster_hurt2", center())
	hit.emit(h)
	return true

## Where its hit box is (the hit effect's place).
func center() -> Vector2:
	var cs := get_parent().get_child(0) as CollisionShape2D
	return cs.global_position if cs != null else global_position
