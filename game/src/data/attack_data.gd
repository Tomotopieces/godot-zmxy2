class_name AttackData
extends Resource
## One attack (melee swing, skill or projectile). All units are px / seconds.

enum Kind { PHYSICS, MAGIC, TRUE }

@export var power_mul := 1.0          ## damage = attacker attack * power_mul (+ flat)
@export var flat := 0                 ## fixed damage (monsters, hit7)
@export var kind := Kind.PHYSICS
@export var knockback := Vector2.ZERO ## px/s, x is "away from attacker"
@export var push_from_center := false ## knockback direction from hitbox center instead of facing
@export var rehit_interval := 0.0     ## projectiles: seconds until the same target can be hit again (0 = never)
@export var max_hits := 1             ## projectiles: total hits before it is spent

@export_group("Feel")
@export var hitstop := 0.0            ## seconds the attacker (melee) and the target freeze when it lands (x1.5 on a crit)
@export var hitstop_once := false     ## multi-hit moves: only the first round of hits stops
@export var shake := 0.0              ## camera trauma (0..1) added by the first target of each round
@export var rumble := 0.0             ## gamepad rumble strength (0..1) of each round

@export_group("Skill")
@export var mp_cost := 0
@export var cooldown := 0.0           ## seconds before the next attack input is accepted
@export var dash_speed := 0.0
@export var rage_dash_speed := 0.0
@export var invincible := 0.0
@export var extra := {}               ## skill specific numbers (already converted)
@export var effect_only := false      ## puts its effects on the target without damage or hit stun (the 都市王 net)
@export var effects: Array = []       ## status effects put on the target: {name, time (s), power, tick (s)}

@export_group("Projectile")
@export var projectile := ""          ## rig name spawned by the attack
@export var spawn_offset := Vector2.ZERO
@export var speed := 0.0
@export var distance := 0.0
@export var spin_deg := 0.0
@export var spin_time := 0.0
