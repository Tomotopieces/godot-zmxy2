class_name Rig
extends Node2D
## An animated body (characters, effects, bullets, items): the hand-editable scene scenes/actors/<name>/<name>.tscn.
##
## Children:
##   Poses/<Action>/...   Sprite2D parts (and EquipSlot nodes) of each action; only the playing action is visible
##   Hitbox, Hurtbox      Area2D whose shapes are animated per action
##   Anim                 AnimationPlayer with one animation per action; gameplay events are named method keys
##                        (ev_new_hit, ev_finished, ev_set_vx(v) ...), frame 0 included
##
## The art faces left. `facing` = 1 means facing right (rig mirrored).

signal event(name: StringName, args: Array)   ## gameplay event keyed in the animation
signal action_finished(action: StringName)

@export var actions: PackedStringArray
@export var markers: Dictionary = {}   ## named anchor points of the rest pose (e.g. "levelupmc")
@onready var anim: AnimationPlayer = $Anim
var hitbox: Area2D:   ## what this rig hits with (animated per action)
	get:
		return get_node("Hitbox")
var hurtbox: Area2D:   ## where this rig can be hit (null when the scene has none, e.g. a bullet)
	get:
		return get_node_or_null("Hurtbox")

var action: StringName = &""
var equipment := {}    ## slot kind -> variant id (cloth / cloth_ex / weapon / wing)

var _parts: Node2D
var _current_parts: Node2D
var _flash_mat: ShaderMaterial
var _flash_tween: Tween

const HIT_FLASH := preload("res://src/rig/hit_flash.gdshader")

## The rig's material (flash + stage light) and every part without a material of its own using it.
func _adopt_parts() -> void:
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = HIT_FLASH
		material = _flash_mat
	for n: Node2D in find_children("*", "Node2D", true, false):
		if n.material == null and not n.use_parent_material:
			n.use_parent_material = true

## A stage's light on this body: multiplier `shade` at the feet, `lit` at `height` px above them.
func set_light(shade: Color, lit: Color, height: float, rim := 0.0, rim_width := 1.6) -> void:
	_adopt_parts()
	_flash_mat.set_shader_parameter("rim_strength", rim)
	_flash_mat.set_shader_parameter("rim_width", rim_width)
	_flash_mat.set_shader_parameter("look_on", true)
	_flash_mat.set_shader_parameter("shade", shade)
	_flash_mat.set_shader_parameter("lit", lit)
	_flash_mat.set_shader_parameter("body_height", height)

## Where the feet are now (world y), for the light gradient; call every tick while lit.
func set_feet(y: float) -> void:
	if _flash_mat != null:
		_flash_mat.set_shader_parameter("feet_y", y)

## A hit lands: the whole rig flashes `color` for `secs` (fading out). Parts that carry an effect material of their
## own (glows, blurs) keep it; everything else takes the flash through the rig's material.
func flash(color: Color, secs := 0.1) -> void:
	_adopt_parts()
	_flash_mat.set_shader_parameter("flash_color", color)
	_flash_mat.set_shader_parameter("flash", 0.85)
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_mat, "shader_parameter/flash", 0.0, secs)

func _ready() -> void:
	# Only the owner's movement is interpolated; keyed part jumps and facing flips must land on their frame.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_parts = $Poses
	for c in _parts.get_children():
		c.visible = false
	anim.animation_finished.connect(_on_anim_finished)

## An action with a loop tail (an opening, then a looping part) keeps looping instead of finishing.
func _on_anim_finished(n: StringName) -> void:
	var an := anim.get_animation(n)
	if an and an.has_meta(&"loop_from") and n == action:
		anim.play(n)
		anim.seek(float(an.get_meta(&"loop_from")), true)
		return
	action_finished.emit(n)

## Play an action from its start (restart=false keeps playing when already in it). Keys at time 0 are not fired by the
## seek: they are emitted here, in track order.
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

## The node holding the parts of the playing action (null before the first play).
func current_pose() -> Node2D:
	return _current_parts

func pause() -> void:
	anim.pause()

func resume() -> void:
	anim.play()

func is_playing() -> bool:
	return anim.is_playing()

## The action's one-shot part is over (finished, or looping its tail).
func settled() -> bool:
	if not anim.is_playing():
		return true
	var an := anim.get_animation(action)
	return an != null and an.has_meta(&"loop_from") and anim.current_animation_position >= float(an.get_meta(&"loop_from"))

## Draw the whole rig additively: effects authored as light on a black background (the original blends them with "add").
func set_additive() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for sp: Sprite2D in find_children("*", "Sprite2D", true, false):
		if sp.material is ShaderMaterial:
			var m := (sp.material as ShaderMaterial).duplicate() as ShaderMaterial
			m.shader = SpriteFx.SHADER_ADD
			sp.material = m
		else:
			sp.material = mat

## Whether an action carries frame events (a script that ends it, drops, destroys ...).
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

## Seconds into the current action.
func time() -> float:
	return anim.current_animation_position

## Normalized progress of the current action (0..1).
func progress() -> float:
	if anim.current_animation == "":
		return 1.0
	return anim.current_animation_position / maxf(anim.current_animation_length, 0.0001)

## Equip a variant on every slot of the given kind ("cloth", "weapon", "wing").
func set_equip(kind: String, id: int) -> void:
	equipment[kind] = id
	for s in find_children("*", "EquipSlot", true, false):
		if s.kind == kind or (kind == "cloth" and s.kind == "cloth_ex"):
			s.set_variant(id)
	if _flash_mat != null:
		_adopt_parts.call_deferred()   # (the new variant's parts take the rig's material too)

## Jump the current action to just before its first event `n` whose first argument is `arg` (original gotoAndPlay(frame)).
## Deferred: this is usually called from an animation event, and seeking the player inside its own callback crashes.
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

## Seek without processing keys (update would re-fire method keys); playback triggers the target event next tick.
func _seek_in(a: StringName, t: float) -> void:
	if action == a and anim.is_playing():
		anim.seek(t, false)

## Makes this rig show exactly what `src` shows now: same action and moment (also of the animated equipment), same
## equipment, transform and tint. Used for a halo drawn behind the real rig.
func mirror(src: Rig) -> void:
	if src.action != action:
		play(src.action, true)
		anim.pause()
	for k in src.equipment:
		if equipment.get(k) != src.equipment[k]:
			set_equip(k, src.equipment[k])
	anim.seek(src.anim.current_animation_position, true)
	var mine := find_children("*", "AnimationPlayer", true, false)
	var theirs := src.find_children("*", "AnimationPlayer", true, false)
	if mine.size() == theirs.size():
		for i in mine.size():
			var p: AnimationPlayer = mine[i]
			var q: AnimationPlayer = theirs[i]
			if p != anim and p.current_animation != "":
				p.seek(q.current_animation_position, true)
	transform = src.transform
	visible = src.visible
	modulate = src.modulate

## Frozen copy of the current pose in world space (afterimages), without effects.
func make_ghost() -> Node2D:
	if _current_parts == null:
		return null
	var ghost := Node2D.new()
	ghost.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for sp: Sprite2D in _current_parts.find_children("*", "Sprite2D", true, false):
		if not sp.is_visible_in_tree() or sp.texture == null:
			continue
		var g := Sprite2D.new()
		g.texture = sp.texture
		g.centered = sp.centered
		g.region_enabled = sp.region_enabled   # a cropped part (Flash mask) draws only its region
		g.region_rect = sp.region_rect
		g.offset = sp.offset
		g.transform = sp.global_transform
		var tint := Color.WHITE
		var n: Node = sp
		while n != null and n != get_parent():
			if n is CanvasItem:
				tint *= (n as CanvasItem).modulate
			n = n.get_parent()
		g.self_modulate = tint
		ghost.add_child(g)
	return ghost

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

## Global AABB of a box (Hitbox / Hurtbox) of any shape as set in the scene; empty Rect2 while the box is off or missing.
func box_rect(area: Area2D) -> Rect2:
	if area == null or area.get_child_count() == 0:
		return Rect2()
	var cs := area.get_child(0) as CollisionShape2D
	if cs == null or cs.disabled or cs.shape == null:
		return Rect2()
	return cs.global_transform * cs.shape.get_rect()

func hit_rect() -> Rect2:
	return box_rect(hitbox)

func hurt_rect() -> Rect2:
	return box_rect(hurtbox)

static var _scenes := {}
static var _loading := {}   ## rig name -> path being loaded in the background

static func _path(rig_name: String) -> String:
	return "res://scenes/actors/%s/%s.tscn" % [rig_name, rig_name]

## Container name of an action ("hit10" -> "Hit10", "hit2-1" -> "Hit2And1").
static func pose_name(a: String) -> String:
	return a.replace("-", "And").to_pascal_case()

## Rig scene by name (cached).
static func scene(rig_name: String) -> PackedScene:
	if not _scenes.has(rig_name):
		if _loading.has(rig_name):
			_scenes[rig_name] = ResourceLoader.load_threaded_get(_loading[rig_name])
			_loading.erase(rig_name)
		else:
			_scenes[rig_name] = load(_path(rig_name))
	return _scenes[rig_name]

## Start loading rigs in the background (a stage's monsters and their effects), so their first appearance
## does not stall the game while the scene and its textures load.
static func warm(names: Array) -> void:
	for n in names:
		if _scenes.has(n) or _loading.has(n) or not ResourceLoader.exists(_path(n)):
			continue
		if ResourceLoader.load_threaded_request(_path(n)) == OK:
			_loading[n] = _path(n)

static func create(rig_name: String) -> Rig:
	return scene(rig_name).instantiate()
