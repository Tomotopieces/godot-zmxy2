class_name HeroPortrait
## The animated hero of the bag and shop screens: the hero's bag puppet wearing the current look, drawn in place of the
## layout's frozen `personmc` picture, and the spotlight behind it playing.
static func build(ui: UiLayout) -> Puppet:
	var glow := ui.get_piece("spotlight") as Puppet
	if glow:
		glow.play(glow.actions[0])
	var still := ui.get_piece("personmc") as Node2D
	still.visible = false
	var p := Puppet.create("bag_" + GameState.hero_data.role)
	p.position = still.position
	ui.add_child(p)
	ui.move_child(p, still.get_index() + 1)
	p.play(p.actions[0])
	var dress := func() -> void:
		var look := GameState.appearance()
		for k in look:
			p.set_equip(k, look[k])
	dress.call()
	GameState.equipment_changed.connect(dress)
	p.tree_exiting.connect(func(): GameState.equipment_changed.disconnect(dress))
	return p
