extends Node
## Every boss gives its souls (red orbs) when it dies, however it dies. godot --path game --position 6000,6000 res://tools/souls_check.tscn [-- ids]
func _ready() -> void:
	GameState.new_game("wukong"); GameState.level = 30
	var ids := [38, 39, 40, 45, 46, 47, 51, 56, 58, 59, 60, 61, 64, 67, 69, 72, 73, 77, 79, 81]
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		ids = a[0].split(",")
	var st := Vector2i(1, 1)
	if a.size() > 1:
		st = Vector2i(int(a[1].get_slice(",", 0)), int(a[1].get_slice(",", 1)))
	var ps := PlayScreen.create(st); add_child(ps)
	await get_tree().create_timer(0.8, false).timeout
	var lv := ps.level; var h := lv.hero
	h.invincible = 99999.0
	Engine.time_scale = 4.0
	var fails := 0
	for id in ids:
		var md := lv.monster_data(int(id))
		if md == null: continue
		var m := Monster.create(md)
		m.position = h.global_position + Vector2(300, 0)
		lv.add_monster(m)
		var red := [0]
		var watch := func(n: Node): if n is Orb and n.kind == Orb.Kind.RED: red[0] += 1
		lv.world.child_entered_tree.connect(watch)
		var souls0 := GameState.souls
		for k in 60:
			await get_tree().create_timer(0.25, false).timeout
			h.global_position = m.global_position + Vector2(-200, 0) if is_instance_valid(m) else h.global_position
			if not is_instance_valid(m): break
			if m.state != Monster.State.DEAD and m.can_be_hit():
				# a real hit by the hero (sets the target the way play does)
				var hit := Hit.new()
				hit.source = h
				hit.attack = h.data.attacks[&"hit1"]
				hit.action = &"hit1"
				hit.damage = m.max_hp * 10
				hit.direction = 1
				m.take_hit(hit)
			elif m.state != Monster.State.DEAD:
				m.invuln = 0.0
		await get_tree().create_timer(2.0, false).timeout
		lv.world.child_entered_tree.disconnect(watch)
		var ok: bool = red[0] > 0 or md.souls == 0
		print("%s  monster %d souls=%d red orbs=%d gained=%d alive=%s" % ["ok  " if ok else "FAIL", int(id), md.souls, red[0], GameState.souls - souls0, is_instance_valid(m)])
		if not ok: fails += 1
		if is_instance_valid(m): m.queue_free()
		for c in lv.monsters(): c.queue_free()
		await get_tree().create_timer(0.2, false).timeout
	print("SOULS CHECK ", "FAILED (%d)" % fails if fails else "OK")
	get_tree().quit(1 if fails else 0)
