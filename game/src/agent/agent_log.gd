class_name AgentLog
## Combat feedback for AI 接入 (AgentBridge): what the screen shows as it happens - damage numbers, MISS, heals.
## The game calls report(); nothing happens unless an agent is connected.

static var sink: Callable   ## set by AgentBridge while connected

static func report(d: Dictionary) -> void:
	if sink.is_valid():
		sink.call(d)
