extends Node
## Press a skill and log the hero state every physics tick: godot ... -- <keys comma separated> [air] [role=<name>]
var _t := 0.0
var _keys: PackedStringArray
var _air := false
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var role := "wukong"
	var rest := PackedStringArray()
	for arg in a:
		if arg.begins_with("role="):
			role = arg.substr("role=".length())
		else:
			rest.append(arg)
	_keys = rest[0].split(",")
	_air = rest.size() > 1 and rest[1] == "air"
	GameState.new_game(role)
	for s in GameState.hero_data.learn_active:
		GameState.skills[StringName(s)] = true
	add_child(PlayScreen.create(Vector2i(1, 1)))
func _physics_process(delta: float) -> void:
	_t += delta
	var lv := Level.current
	if lv == null or not is_instance_valid(lv.hero):
		return
	var h := lv.hero
	if _t > 1.5 and _t < 1.5 + delta * 1.5:
		if _air:
			Input.action_press("jump")
	if _t > (1.75 if _air else 1.5) and _t < (1.75 if _air else 1.5) + delta * 1.5:
		Input.action_release("jump")
		for k in _keys:
			Input.action_press(k)
	if _t > 1.6 and not _air or _t > 1.85:
		for k in _keys:
			Input.action_release(k)
	if _t > 1.4 and int(_t * 60) % 3 == 0:
		print("t=%.2f st=%s act=%s prog=%.2f pos=(%.0f,%.0f) v=(%.0f,%.0f) floor=%s cd=%.2f mp=%d nograv=%s noinput=%s" % [_t, Hero.State.keys()[h.state], h.rig.action, h.rig.progress(), h.global_position.x, h.global_position.y, h.velocity.x, h.velocity.y, h.is_on_floor(), h.cooldown, h.mp, h._no_gravity, h._no_input])
	if _t > 3.2:
		get_tree().quit()
