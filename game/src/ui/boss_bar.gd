class_name BossBar
extends Node2D
## Boss HP gauge at the top of the screen (scenes/ui/boss_blood.tscn): the red Gauge (a TextureProgressBar) empties
## from the right as HP drops. The BossName label is placed in the scene with its centre on the gauge's left edge;
## it grows both ways, so a name of any length stays centred there.

var boss: Monster
var _ui: UiLayout
var _gauge: Range

static func create(m: Monster) -> BossBar:
	var b := BossBar.new()
	b.boss = m
	return b

func _ready() -> void:
	_ui = UiLayout.create("boss_blood")
	add_child(_ui)
	_gauge = _ui.get_piece("gauge")
	_ui.set_text("boss_name", boss.data.display_name)

func _process(_dt: float) -> void:
	if not is_instance_valid(boss) or boss.state == Monster.State.DEAD:
		queue_free()
		return
	_gauge.value = clampf(float(boss.hp) / boss.max_hp, 0.0, 1.0)
