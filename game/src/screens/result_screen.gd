class_name ResultScreen
extends CanvasLayer
## Stage result (export.win.GameWin / export.lose.GameFail).
## Win: time, best combo, state %, score; buttons next stage (main path stages 1-3 only) / back to map.
## Fail: retry (not for hidden stages 5+) / back to map.

signal next
signal retry
signal back

var _ui: UiLayout

static func win(stage: Vector2i, stats: Dictionary) -> ResultScreen:
	var r := ResultScreen.new()
	r._ui = UiLayout.create("game_win")
	var t: float = stats.time
	# score = time part (capped 800) + state part (capped 300) + best combo (capped 800), as GameWin.setScore
	var time_score := mini(int((300.0 + t) / maxf(t * 50.0, 0.001)), 800)
	var state_score := mini(int(3.0 * stats.state), 300)
	var combo_score := mini(int(stats.combo), 800)
	r._ui.set_text("txt_usertime", "%d:%02d" % [int(t) / 60, int(t) % 60])
	r._ui.set_text("txt_hight", str(stats.combo))
	r._ui.set_text("txt_state", "%d%%" % mini(int(stats.state), 100))
	r._ui.set_text("txt_allscore", str(time_score + state_score + combo_score))
	r._ui.set_visible_piece("nextStageButton", stage.x <= 3)
	return r

static func fail(stage: Vector2i) -> ResultScreen:
	var r := ResultScreen.new()
	r._ui = UiLayout.create("game_fail")
	r._ui.set_visible_piece("rePlayButton", stage.x < 5)
	return r

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Level.VIEW
	add_child(dim)
	add_child(_ui)
	_ui.button_pressed.connect(_on_button)

func _on_button(b: String) -> void:
	match b:
		"nextStageButton": next.emit()
		"rePlayButton": retry.emit()
		"backTochooseButton": back.emit()
