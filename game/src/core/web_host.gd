class_name WebHost
extends Node
## Web build embedded in the player site: the page posts {zmxy2: "hidden" | "visible"} when its 开始游戏 tab is left or
## shown again (web_shell/shell.html stores it in window.__zmxy2Hidden). While hidden the sound is off and a running
## stage opens its pause menu, so the game does not play on behind another tab.

const POLL := 0.25

static var hidden := false   ## the site has hidden the game (Snd keeps the master bus muted)
var _t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	_t += delta
	if _t < POLL:
		return
	_t = 0.0
	var h: bool = JavaScriptBridge.eval("window.__zmxy2Hidden === true", true)
	if h == hidden:
		return
	hidden = h
	Snd.apply()
	if h:
		for p in get_tree().root.find_children("*", "PlayScreen", true, false):
			p.open_pause()
