extends Node
## 刑天门 (StageListener22/23/111): stands at one of the stage's spots. Only a hero carrying the 阎罗令 (yll) can use
## it: touching it for a while (time is not reset when stepping away) opens it, then walking into the doorway uses
## up the key and leads to 刑天 (7-1).

var stage: StageScript
var cfg: Dictionary
var _door: Rig
var _touch := 0.0
var _open := false

func _ready() -> void:
	var spots: Array = stage.param("xingtian_door", {}).get("positions", [])
	if spots.is_empty():
		return
	var s: Array = spots[randi() % spots.size()]
	_door = stage.place_rig("xingtian_door", Vector2(s[0], s[1]))
	_touch = float(cfg.touch)

func _physics_process(delta: float) -> void:
	if _door == null or not GameState.has_item(String(cfg.key)):
		return
	if not _open:
		var t: Array = cfg.touch_box
		if stage.hero_in(Rect2(_door.position + Vector2(t[0], t[1]), Vector2(t[2], t[3]))):
			_touch -= delta
			if _touch <= 0.0:
				_open = true
				var pos := _door.position
				_door.queue_free()
				_door = stage.place_rig("xingtian_door_open", pos)
		return
	if not _door.settled():
		return   # the doorway opens once the door has swung open (the vortex then keeps turning)
	var e: Array = cfg.enter_rect
	if stage.hero_in(Rect2(_door.position + Vector2(e[0], e[1]), Vector2(e[2], e[3]))):
		if GameState.take_item(String(cfg.key)):
			stage.level.go_to(Vector2i(cfg.to[0], cfg.to[1]))
