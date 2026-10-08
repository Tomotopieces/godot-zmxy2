extends Node
## Regression: use skills while being hit. godot --path game res://tools/hurt_skill_test.tscn -- <key> [monster id]
var _t := 0.0
var _key := "skill_u"
var _id := 31
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: _key = a[0]
	if a.size() > 1: _id = int(a[1])
	GameState.new_game()
	for s in GameState.hero_data.learn_active:
		GameState.skills[StringName(s)] = true
	add_child(PlayScreen.create(Vector2i(1, 1)))
func _physics_process(delta: float) -> void:
	_t += delta
	var lv := Level.current
	if lv == null or not is_instance_valid(lv.hero):
		return
	var h := lv.hero
	h.mp = h.max_mp
	h.hp = h.max_hp
	if lv.monsters().size() < 3 and int(_t * 10) % 10 == 0:
		var m := Monster.create(lv.monster_data(_id))
		m.position = h.global_position + Vector2(randf_range(-80, 80), -20)
		lv.add_monster(m)
	var on := int(_t * 60) % 3 == 0
	if on: Input.action_press(_key)
	else: Input.action_release(_key)
	if int(_t * 60) % 30 == 0:
		print("t=%.1f st=%s act=%s pos=%.3f playing=%s spd=%.2f paused=%s v=%s inv=%.2f x=%.0f" % [_t, Hero.State.keys()[h.state], h.rig.action, h.rig.anim.current_animation_position, h.rig.anim.is_playing(), h.rig.anim.speed_scale, get_tree().paused, h.velocity, h.invincible, h.global_position.x])
	if _t > 20.0:
		get_tree().quit()
