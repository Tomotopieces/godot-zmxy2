class_name ActorBody
extends Rig
## A hand-editable actor scene (scenes/actors/<name>/<name>.tscn, made once by tools/rig_to_actor.gd).
## Same API as Rig. Differences: the action containers are Poses/<Action> (PascalCase), and the gameplay events are
## named method keys (ev_new_hit, ev_finished, ev_set_vx(v) ...) on the animations, frame 0 included.

## Container name of an action ("hit10" -> "Hit10", "hit2-1" -> "Hit2And1").
static func pose_name(a: String) -> String:
	return a.replace("-", "And").to_pascal_case()

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_parts = $Poses
	for c in _parts.get_children():
		c.visible = false
	anim.animation_finished.connect(_on_anim_finished)

func play(a: StringName, restart := false) -> void:
	if a == action and not restart and anim.is_playing():
		return
	if not anim.has_animation(a):
		push_warning("%s: no action %s" % [name, a])
		return
	if _current_parts:
		_current_parts.visible = false
	_current_parts = _parts.get_node_or_null(NodePath(pose_name(String(a))))
	if _current_parts:
		_current_parts.visible = true
	action = a
	anim.play(a)
	anim.seek(0.0, true)
	# keys at time 0 are not fired by the seek above: emit them here, in track order
	var an := anim.get_animation(a)
	for tr in an.get_track_count():
		if an.track_get_type(tr) != Animation.TYPE_METHOD:
			continue
		for k in an.track_get_key_count(tr):
			if an.track_get_key_time(tr, k) > 0.0001:
				break
			if action != a:
				return
			var m := String(an.method_track_get_name(tr, k))
			if m.begins_with("ev_"):
				event.emit(StringName(m.substr(3)), an.method_track_get_params(tr, k))

## Emit only events whose key really sits at the current moment: keys at time 0 are emitted by play(), and the
## AnimationPlayer also fires the nearest earlier key of every method track after a seek (seek_to_event): those are dropped.
func _emit(n: StringName, args: Array) -> void:
	var pos := anim.current_animation_position
	var an := anim.get_animation(action)
	if an == null:
		return
	var want := StringName("ev_" + String(n))
	for tr in an.get_track_count():
		if an.track_get_type(tr) != Animation.TYPE_METHOD:
			continue
		for k in an.track_get_key_count(tr):
			var t := an.track_get_key_time(tr, k)
			if t > pos + 0.0001:
				break
			if t > 0.0001 and pos - t <= 0.1 and an.method_track_get_name(tr, k) == want and an.method_track_get_params(tr, k) == args:
				event.emit(n, args)
				return

func ev_finished() -> void: _emit(&"finished", [])
func ev_new_hit() -> void: _emit(&"new_hit", [])
func ev_stop_move() -> void: _emit(&"stop_move", [])
func ev_set_vx(v: float) -> void: _emit(&"set_vx", [v])
func ev_set_vy(v: float) -> void: _emit(&"set_vy", [v])
func ev_set_vx_forward(v: float) -> void: _emit(&"set_vx_forward", [v])
func ev_scale_vx(f: float) -> void: _emit(&"scale_vx", [f])
func ev_call(fn: String, a1 = null, a2 = null) -> void: _emit(&"call", [fn] + _rest(a1, a2))
func ev_grounded_call(fn: String, a1 = null, a2 = null) -> void: _emit(&"grounded_call", [fn] + _rest(a1, a2))
func ev_boss_dead_fx() -> void: _emit(&"boss_dead_fx", [])
func ev_shake(v: float) -> void: _emit(&"shake", [v])

func _rest(a1, a2) -> Array:
	var r := []
	if a1 != null: r.append(a1)
	if a2 != null: r.append(a2)
	return r

## Jump to just before the first event `n` whose first argument is `arg`.
func seek_to_event(n: StringName, arg = null) -> void:
	var an := anim.get_animation(action)
	var want := "ev_" + String(n)
	for tr in an.get_track_count():
		if an.track_get_type(tr) != Animation.TYPE_METHOD:
			continue
		for k in an.track_get_key_count(tr):
			if String(an.method_track_get_name(tr, k)) != want:
				continue
			var p: Array = an.method_track_get_params(tr, k)
			if arg == null or (p.size() > 0 and p[0] == arg):
				_seek_in.call_deferred(action, maxf(an.track_get_key_time(tr, k) - 0.001, 0.0))
				return

func has_events(a: StringName) -> bool:
	var an := anim.get_animation(a)
	if an == null:
		return false
	for tr in an.get_track_count():
		if an.track_get_type(tr) == Animation.TYPE_METHOD and an.track_get_key_count(tr) > 0:
			return true
		if String(an.track_get_path(tr)) == "Poses:visible":
			return true
	return false
