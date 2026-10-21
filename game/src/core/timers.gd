class_name Timers
extends RefCounted
## Game-time timers: a Timer node under `owner`, so it stands still whenever its owner does (pause, a hit-stop of the
## world, a frozen level) and goes away with it.

## Calls `fn` after `seconds` (every `seconds` when `repeat`). The returned Timer can be stopped or restarted.
static func start(owner: Node, seconds: float, fn: Callable, repeat := false) -> Timer:
	var t := Timer.new()
	t.process_callback = Timer.TIMER_PROCESS_PHYSICS
	t.one_shot = not repeat
	t.wait_time = maxf(seconds, 0.001)
	t.timeout.connect(fn)
	if not repeat:
		t.timeout.connect(t.queue_free)
	owner.add_child(t)
	t.start()
	return t
