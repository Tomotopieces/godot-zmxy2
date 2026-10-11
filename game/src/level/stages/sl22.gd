extends StageScript
## 2-2 (StageListener22): 判官's six fires. A while after the boss appears the fires fly from him to their braziers;
## when they are lit the fight starts. Every interval one fire goes out; when the last is out the stage is lost.
## (Fix of the original: the countdown stops when 判官 dies.)

var _cfg: Dictionary
var _boss: Monster
var _fires: Array[Rig] = []
var _t := -1.0
var _lose_t := -1.0

func setup() -> void:
	_cfg = param("panguan", {})
	add_xingtian_door()

func on_monster_added(m: Monster) -> void:
	if m.data.id != int(_cfg.get("boss", 39)) or _boss != null:
		return
	_boss = m
	get_tree().create_timer(float(_cfg.intro), false).timeout.connect(_light_fires)

## start1: the fires leave the boss and fly to their places; the first arrival starts the fight (start2).
func _light_fires() -> void:
	if not is_instance_valid(_boss):
		return
	var started := false
	for target in _cfg.targets:
		var f := place_rig("panguan_fire", _boss.center())
		_fires.append(f)
		var tw := f.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(f, "position", Vector2(target[0], target[1]), float(_cfg.fly))
		if not started:
			started = true
			tw.tween_callback(_start_fight)

func _start_fight() -> void:
	if is_instance_valid(_boss):
		_boss.brain.real_start()
	_t = float(_cfg.fire_out)

func _physics_process(delta: float) -> void:
	if _t < 0.0:
		return
	if not is_instance_valid(_boss) or _boss.state == Monster.State.DEAD:
		_t = -1.0
		return
	if _lose_t >= 0.0:
		_lose_t -= delta
		if _lose_t < 0.0:
			level.fail()
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = float(_cfg.fire_out)
	var f: Rig = _fires.pop_front()
	if f:
		var pos := f.position
		var tw := f.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(f, "modulate:a", 0.0, float(_cfg.fade))
		tw.tween_callback(func():
			f.queue_free()
			place_rig("panguan_fire_out", pos))
	if _fires.is_empty():
		_lose_t = float(_cfg.lose_after)
