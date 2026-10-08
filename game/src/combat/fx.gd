class_name Fx
extends Node2D
## Visual-only one-shot rig (hit sparks, skill flashes). Frees itself when the animation ends.

static func spawn(rig_name: String, pos: Vector2, facing := -1, scale_mul := 1.0) -> Fx:
	var fx := Fx.new()
	var r := Rig.create(rig_name)
	fx.add_child(r)
	r.scale = Vector2(-facing * scale_mul, scale_mul)
	r.action_finished.connect(func(_a): fx.queue_free())
	r.event.connect(func(n, a): if n == &"destroy" or n == &"finished" or (n == &"call" and not a.is_empty() and a[0] == "destroy"): fx.queue_free())
	fx.position = pos
	fx.z_index = Level.Z_EFFECT
	Level.current.add_object(fx)
	r.play(r.actions[0])
	# looping clips (stop()-gated in the original) play once
	var an := r.anim.get_animation(r.actions[0])
	if an.loop_mode != Animation.LOOP_NONE:
		fx.get_tree().create_timer(an.length, false, true).timeout.connect(fx.queue_free)
	return fx

## Effect that follows a node (level-up glow on the hero).
static func attach(rig_name: String, parent: Node2D, offset := Vector2.ZERO) -> Fx:
	var fx := spawn(rig_name, Vector2.ZERO)
	fx.reparent(parent, false)
	fx.position = offset
	fx.reset_physics_interpolation()
	return fx
