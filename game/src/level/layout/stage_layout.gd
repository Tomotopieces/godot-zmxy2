@tool
class_name StageLayout
extends Node2D
## A stage's playing field (Scenery/Layout in scenes/levels/<stage>.tscn): `size` = the stage's extent; Walls holds the
## floors (StaticBody2D, collision layer 1) and the bodies a stage script moves or switches (AnimatableBody2D: floating
## platforms on the one-way layer 2, hidden walls with a disabled shape); Stops the camera stops (CameraStop, each
## with its MonsterSpawn points); ExitDoor (when the stage has one) the exit portal with its EnterZone.

@export var size := Vector2(940, 590)
