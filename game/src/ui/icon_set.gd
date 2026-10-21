class_name IconSet
extends Sprite2D
## A picture that shows one of a set of icons (a skill icon per hero, the level number): `index` picks it.

@export var icons: Array[Texture2D] = []
@export var index := 0:
	set(v):
		index = v
		if v >= 0 and v < icons.size():
			texture = icons[v]
