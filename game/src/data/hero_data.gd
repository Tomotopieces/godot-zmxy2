class_name HeroData
extends Resource
## Hero tuning (data/<hero>.tres). Units: px, seconds.

## Who this is: id (file name / save key), index (HUD portrait, shop and bag pages), names, rig and sound prefix.
@export var role := "wukong"
@export var role_index := 0
@export var title := "孙悟空"        ## name shown in the bag
@export var character := "悟空"      ## matches EquipmentData.user
@export var sound_prefix := "Role1"
@export var rig := "wukong"
@export var super_armor_in_rage := true      ## no hit stun / knockback while transformed
@export var damage_taken_mul_in_rage := 1.0
@export var lock_glow := Color.RED           ## anti-lock protection glow

## Numbers only this hero's moves use (charge time, shadow, stab count ...), units converted.
@export var kit := {}

@export_group("Movement")
@export var walk_speed := 0.0
@export var run_speed := 0.0
@export var gravity := 0.0
@export var jump_velocity := 0.0
@export var rage_gravity := 0.0
@export var rage_jump_velocity := 0.0
@export var rage_speed_mul := 1.0
@export var double_tap_window := 0.5
@export var drop_through := 20.0

@export_group("Stats")
@export var hp_base := 80
@export var hp_per_level := 50
@export var mp_base := 50
@export var mp_per_level := 20
@export var atk_base := 10
@export var atk_rand := 4
@export var atk_per_level := 5
@export var def_base := 2
@export var def_per_level := 2
@export var def_cap_level := 15
@export var def_per_level_after := 5
@export var exp_table: PackedInt32Array    ## exp to the next level for levels 1..size
@export var exp_step_after_table := 5000   ## beyond the table: last entry + step per level
@export var level_max := 75

@export_group("Rage")
@export var rage_max := 100
@export var rage_hit_gain := 2.0
@export var rage_decay_interval := 1.0   ## seconds per -1 while not full
@export var rage_drain_interval := 0.0   ## seconds per -1 while transformed
@export var rage_freeze := 1.0           ## hit-stop when transforming

@export_group("Anti lock")
@export var lock_hits := 5
@export var lock_window := 1.0
@export var lock_invincible := 2.0

@export_group("Combo")
@export var input_buffer := 0.12   ## seconds an early attack / skill / jump press is kept until it can be done
@export var combo_cooldowns: PackedFloat32Array  ## cooldown set when starting hit N+1, indexed by previous step
@export var air_cooldown := 0.0
@export var combo_reset := 1.0
@export var cancel_progress := 0.7

@export var attacks: Dictionary = {}     ## action name -> AttackData

@export var treasures := {}   ## magic treasure behaviour numbers

@export_group("Learning")
@export var learn_active: PackedStringArray      ## skill actions in shop order
@export var learn_active_cost: PackedInt32Array  ## souls
@export var learn_passive: PackedStringArray     ## stat per passive skill
@export var passive_max := 5
@export var passive_cost_per_level := 5000
@export var passive_bonus := {}                  ## stat -> Vector2(a, b): level n gives a*n + b

## Icon frame of the first learnable skill in the HUD (role_info skill1..5: 0 = locked, then 5 frames per hero).
func hud_icon_base() -> int:
	return role_index * 5 + 1

func passive_value(stat: String, lv: int) -> float:
	if lv <= 0:
		return 0.0
	var ab: Vector2 = passive_bonus.get(stat, Vector2.ZERO)
	return ab.x * lv + ab.y

func max_hp(level: int) -> int:
	return hp_base + hp_per_level * (level - 1)

func max_mp(level: int) -> int:
	return mp_base + mp_per_level * (level - 1)

func attack_power(level: int) -> int:
	return atk_base + Rng.randi_range(0, atk_rand) + atk_per_level * (level - 1)

func defense(level: int) -> int:
	if level < def_cap_level:
		return def_base + def_per_level * (level - 1)
	return def_base + def_per_level * (def_cap_level - 2) + def_per_level_after * (level - def_cap_level + 1)

func exp_to_next(level: int) -> int:
	if level <= exp_table.size():
		return exp_table[level - 1]
	return exp_table[-1] + exp_step_after_table * (level - exp_table.size())
