@tool
class_name CameraStop
extends Marker2D
## A camera stop of a stage (Layout/Stops): the screen locks with its right edge at this x until the monsters spawned
## by its MonsterSpawn children are beaten. `back` = how far left of it the hero may walk while it holds.

@export var back := 1150.0
