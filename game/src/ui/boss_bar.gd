class_name BossBar
extends Node2D
## Boss HP gauge at the top of the screen (GameInfo.addBossBlood / BossBlood): the mask slides left as HP drops
## while the red fill stays put, so the red never leaves the gauge.
## The boss name is the scene's BossName label (marker font, black outline and glow); its centre sits on the left edge
## of the visible red gauge, not on the clip mask's own left edge: the mask texture is far wider than the fill it clips.

const EMPTY_SHIFT := -323.0   ## mask x offset at 0 HP relative to full (BossBlood frame 1 -> frame 100)

var boss: Monster
var _ui: UiLayout
var _mask: Sprite2D
var _mask_x := 0.0
var _gauge_left := 0.0   ## left edge of the visible red gauge (the fill's first opaque pixel) in this BossBar's space, at full HP
var _fill_x := {}   ## fill sprite -> its x (in the mask's space) at full HP

static func create(m: Monster) -> BossBar:
	var b := BossBar.new()
	b.boss = m
	return b

func _ready() -> void:
	_ui = UiLayout.create("boss_blood")
	add_child(_ui)
	for sp: Sprite2D in _ui.find_children("*", "Sprite2D", true, false):
		if sp.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			_mask = sp
	if _mask:
		_mask_x = _mask.position.x
		_gauge_left = _visible_fill_left()
		for c: Node2D in _mask.get_children():
			_fill_x[c] = c.position.x
	_place_name(boss.data.display_name)

## Left edge of the visible red gauge at full HP, in this BossBar's space: the first opaque pixel column of the red fill
## inside the clip mask (the mask texture is much wider than the bar, so the mask's own left edge sits well left of it).
func _visible_fill_left() -> float:
	var left := INF
	for c: Node2D in _mask.get_children():
		if not (c is Sprite2D):
			continue
		var sp := c as Sprite2D
		var x := 0.0
		var img: Image = sp.texture.get_image() if sp.texture != null else null
		if img != null:
			var used := img.get_used_rect()   # the opaque (alpha > 0) pixels
			if used.size.x > 0:
				x = float(used.position.x)   # centered = false, so pixel 0 is the sprite's origin
		left = minf(left, to_local(sp.to_global(Vector2(x, 0))).x)
	return left

func _process(_dt: float) -> void:
	if not is_instance_valid(boss) or boss.state == Monster.State.DEAD:
		queue_free()
		return
	if _mask == null:
		return
	var shift := EMPTY_SHIFT * (1.0 - clampf(float(boss.hp) / boss.max_hp, 0.0, 1.0))
	_mask.position.x = _mask_x + shift
	for c: Node2D in _fill_x:
		c.position.x = _fill_x[c] - shift / _mask.scale.x   # the fill lives in the (scaled) mask's space

## The name's horizontal centre goes on the gauge's left edge; a name wider than the label's box widens it.
func _place_name(t: String) -> void:
	var l := _ui.get_piece("boss_name") as Label
	l.text = t
	l.size.x = maxf(l.size.x, l.get_minimum_size().x)
	l.position.x = _gauge_left - l.size.x * 0.5
