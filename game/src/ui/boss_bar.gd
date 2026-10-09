class_name BossBar
extends Node2D
## Boss HP gauge at the top of the screen (GameInfo.addBossBlood / BossBlood): the mask slides left as HP drops
## while the red fill stays put, so the red never leaves the gauge; namemc shows the boss name by label.

const EMPTY_SHIFT := -323.0   ## mask x offset at 0 HP relative to full (BossBlood frame 1 -> frame 100)

var boss: Monster
var _ui: UiLayout
var _mask: Sprite2D
var _mask_x := 0.0
var _fill_x := {}   ## fill sprite -> its x (in the mask's space) at full HP

static func create(m: Monster) -> BossBar:
	var b := BossBar.new()
	b.boss = m
	return b

func _ready() -> void:
	_ui = UiLayout.create("boss_blood")
	add_child(_ui)
	_ui.show_frame("namemc", boss.data.display_name)
	for sp: Sprite2D in _ui.find_children("*", "Sprite2D", true, false):
		if sp.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			_mask = sp
	if _mask:
		_mask_x = _mask.position.x
		for c: Node2D in _mask.get_children():
			_fill_x[c] = c.position.x

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
