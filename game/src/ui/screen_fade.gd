class_name ScreenFade
extends CanvasLayer
## Screen transition: fades to black, runs the swap while covered, fades back in.
## Input is blocked for the whole transition; runs while paused and ignores bullet time.

const OUT_TIME := 0.18
const IN_TIME := 0.22

var _rect := ColorRect.new()
var _busy := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect.color = Color.BLACK
	_rect.size = Layers.VIEW
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

## Runs swap() under black. A request during a running transition is ignored.
func play(swap: Callable) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := _tween()
	tw.tween_property(_rect, "modulate:a", 1.0, OUT_TIME)
	await tw.finished
	swap.call()
	await get_tree().process_frame   # let the new screen build before it is revealed
	tw = _tween()
	tw.tween_property(_rect, "modulate:a", 0.0, IN_TIME)
	await tw.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false

func busy() -> bool:
	return _busy

func _input(e: InputEvent) -> void:
	if _busy:
		get_viewport().set_input_as_handled()

func _tween() -> Tween:
	return create_tween().set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
