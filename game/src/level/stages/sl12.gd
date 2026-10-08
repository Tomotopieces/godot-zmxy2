extends StageScript
## 1-2 (StageListener12): the white-bone door. Its weak spot sits at a random offset; hit it with new attacks
## enough times and the door opens; then standing in the doorway long enough leads to 白骨精 (5-1).

var _door: Rig
var _hit_box := Rect2()
var _hits := 3
var _last_serial := -1
var _open := false
var _enter_t := 0.0
var _cfg: Dictionary

func setup() -> void:
	_cfg = param("baigu_door", {})
	if _cfg.is_empty():
		return
	var pos := Vector2(_cfg.pos[0], _cfg.pos[1])
	_door = place_rig("baigu_door", pos)
	var hb: Array = _cfg.hit_box
	var off := Vector2(randf_range(_cfg.hit_dx[0], _cfg.hit_dx[1]), randf_range(_cfg.hit_dy[0], _cfg.hit_dy[1]))
	_hit_box = Rect2(pos + off + Vector2(hb[0], hb[1]), Vector2(hb[2], hb[3]))
	_hits = int(_cfg.hits)
	_enter_t = float(_cfg.enter)

func _physics_process(delta: float) -> void:
	if _door == null:
		return
	if not _open:
		var h := level.hero
		if is_instance_valid(h) and h.dealer.serial != _last_serial and hero_hits(_hit_box):
			_last_serial = h.dealer.serial
			Fx.spawn("fx_monster_hurt1" if randf() < 0.5 else "fx_monster_hurt2", _hit_box.get_center())
			_hits -= 1
			if _hits <= 0:
				_open = true
				var pos := _door.position
				_door.queue_free()
				_door = place_rig("baigu_door_open", pos)
		return
	var e: Array = _cfg.enter_rect
	if hero_in(Rect2(_door.position + Vector2(e[0], e[1]), Vector2(e[2], e[3]))):
		_enter_t -= delta
		if _enter_t <= 0.0:
			level.go_to(Vector2i(_cfg.to[0], _cfg.to[1]))
	else:
		_enter_t = float(_cfg.enter)
