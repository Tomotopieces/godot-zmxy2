class_name DropTable
extends Resource
## Loot rules shared by all monsters (BaseMonster.dropAura / addMedicine). Units: px, seconds.

@export var potion_roll := 0.5         ## chance of the HP branch; else MP roll
@export var hp_potion_chance := 0.1
@export var big_hp_chance := 0.05      ## within hp_potion_chance; then 50/50 big/small
@export var mp_potion_chance := 0.1
@export var red_orbs := Vector2i(2, 4)
@export var orb_count_rolls: Array = [[0.04, 3], [0.08, 2], [0.12, 1]]  ## per green/blue/white orb kind

@export_group("Orb motion")
@export var orb_delay := 0.8
@export var orb_rise := Vector2(30, 50)
@export var orb_rise_time := 1.0
@export var orb_speed := Vector2(96, 144)
@export var orb_accel := 0.0           ## px/s^2
@export var orb_max_speed := 480.0
@export var orb_pickup := 10.0
@export var orb_life := 100.0

@export_group("Restore")
@export var orb_hp_ratio := 0.05
@export var orb_mp_ratio := 0.05
@export var orb_min_restore := 10
@export var white_rage := 5
@export var small_hp := 100
@export var big_hp := 200
@export var small_mp := 100
@export var potion_life := 10.0
