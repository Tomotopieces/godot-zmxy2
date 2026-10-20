extends StageScript
## 2-2 (StageListener22): 判官's six fires. A while after the boss appears the fires fly from him to their braziers;
## when they are lit the fight starts. Every interval one fire goes out; when the last is out the stage is lost.
## (Fix of the original: the countdown stops — and every 命灯 still burning or flying goes out — when 判官 dies.)

var _cfg: Dictionary
var _boss: Monster
var _fires: Array[Puppet] = []
var _t := -1.0
var _lose_t := -1.0

func setup() -> void:
	_cfg = param("panguan", {})

func on_monster_added(m: Monster) -> void:
	if m.data.id != int(_cfg.get("boss", 39)) or _boss != null:
		return
	_boss = m
	get_tree().create_timer(float(_cfg.intro), false).timeout.connect(_light_fires)

## start1: the fires leave the boss and fly to their places; the first arrival starts the fight (start2).
func _light_fires() -> void:
	if not is_instance_valid(_boss) or _boss.state == Monster.State.DEAD:
		return
	var started := false
	for target in _cfg.targets:
		var f := place_puppet("panguan_fire", _boss.center())
		_fires.append(f)
		var tw := f.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		f.set_meta(&"fly", tw)   # a fire still on its way can be stopped if 判官 dies meanwhile
		tw.tween_property(f, "position", Vector2(target[0], target[1]), float(_cfg.fly))
		if not started:
			started = true
			tw.tween_callback(_start_fight)

func _start_fight() -> void:
	if is_instance_valid(_boss):
		_boss.brain.real_start()
	_t = float(_cfg.fire_out)

## 判官 died: the countdown stops and every remaining 命灯 — burning or still flying to its brazier — fades out
## (over `fade`) and is freed, so no fire is left on screen.
func _douse_fires() -> void:
	_t = -1.0
	_lose_t = -1.0
	for f: Puppet in _fires:
		if not is_instance_valid(f):
			continue
		if f.has_meta(&"fly"):
			var fly: Tween = f.get_meta(&"fly")
			if fly.is_valid():
				fly.kill()   # a fire that has not arrived must not start the fight any more
		var tw := f.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(f, "modulate:a", 0.0, float(_cfg.fade))
		tw.tween_callback(f.queue_free)
	_fires.clear()

func _physics_process(delta: float) -> void:
	if _fires.is_empty() and _t < 0.0:
		return   # nothing is burning and no countdown runs (the fires did not leave 判官 yet, or are all out)
	if not is_instance_valid(_boss) or _boss.state == Monster.State.DEAD:
		_douse_fires()
		return
	if _t < 0.0 and _lose_t < 0.0:
		return   # the fires are still flying to their braziers: the countdown starts when the first one arrives (_start_fight)
	if _lose_t >= 0.0:
		_lose_t -= delta
		if _lose_t < 0.0:
			level.fail()
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = float(_cfg.fire_out)
	var f: Puppet = _fires.pop_front()
	if f:
		var pos := f.position
		var tw := f.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tw.tween_property(f, "modulate:a", 0.0, float(_cfg.fade))
		tw.tween_callback(func():
			f.queue_free()
			place_puppet("panguan_fire_out", pos))
	if _fires.is_empty():
		_lose_t = float(_cfg.lose_after)
