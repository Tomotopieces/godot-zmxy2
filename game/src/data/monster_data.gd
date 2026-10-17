class_name MonsterData
extends Resource
## Monster tuning (data/monsters/monster_<id>.tres). Units: px, seconds.

@export var id := 0
@export var display_name := ""
@export var rig := ""
@export var is_boss := false

@export_group("Stats")
@export var speed := 0.0
@export var hp := 1
@export var def := 0
@export var mdef := 0.0
@export var exp := 0
@export var souls := 0             ## red orb power ("gxp" in the original)

@export_group("AI")
@export var sight := 300.0
@export var attack_range := 80.0
@export var attack_chance := 50    ## percent per attack check
@export var attack_check := 1.5    ## seconds between attack decisions in range
@export var think_walk_at := 0.5   ## wander: seconds into the cycle when a direction is picked
@export var walk_times := PackedFloat32Array([3.0, 4.0])
@export var wander_rest := 1.0     ## random extra idle after a walk
@export var knockback_decay := 0.0 ## velocity multiplier per second while faster than walk speed
@export var gravity := 0.0
@export var hp_bar_time := 2.0
@export var hp_bar_fade := 1.0
@export var move_while_attacking: PackedStringArray

@export_group("Drops")
@export var equip_chance := 0.15
@export var stone_rate := 0.0     ## boss: chance of a 1级强化石
@export var equip_drops: PackedStringArray

@export var attacks: Dictionary = {}   ## action -> AttackData

@export_group("Behaviour")
@export var brain_type := ""           ## shared brain script (boss_b, boss_d ...); brain_<id>.gd wins if present
@export var brain := {}                ## brain parameters (frames already converted to seconds)
@export var behind := false            ## drawn right above the background, behind every character (MainGame.createMonster)
@export var is_prop := false           ## scenery that can be hit: no damage numbers, HP bar, exp or combo
@export var immovable := false         ## not pulled / pushed (totems, props)
