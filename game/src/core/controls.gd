class_name Controls
extends RefCounted
## Default gamepad bindings (the keyboard ones live in project.godot) and the F11 fullscreen toggle.

## Gamepad: X attack, A jump, B treasure, RB 烈焰闪, RT 火魔斩, Y 烈焰风暴, LB run (hold), LT skill L (唐僧 / 八戒's fifth skill);
## D-pad / left stick move, R3 rage, Back bag, Start pause.
const PAD_BUTTONS := {
	&"attack": [JOY_BUTTON_X], &"jump": [JOY_BUTTON_A], &"treasure": [JOY_BUTTON_B],
	&"skill_u": [JOY_BUTTON_RIGHT_SHOULDER], &"skill_i": [JOY_BUTTON_Y], &"run": [JOY_BUTTON_LEFT_SHOULDER],
	&"rage": [JOY_BUTTON_RIGHT_STICK], &"open_bag": [JOY_BUTTON_BACK], &"pause": [JOY_BUTTON_START],
	&"move_left": [JOY_BUTTON_DPAD_LEFT], &"move_right": [JOY_BUTTON_DPAD_RIGHT],
	&"move_up": [JOY_BUTTON_DPAD_UP], &"move_down": [JOY_BUTTON_DPAD_DOWN],
}
const PAD_AXES := {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0], &"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"move_up": [JOY_AXIS_LEFT_Y, -1.0], &"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	&"skill_o": [JOY_AXIS_TRIGGER_RIGHT, 1.0], &"skill_l": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

static func add_gamepad_defaults() -> void:
	if not InputMap.has_action(&"run"):
		InputMap.add_action(&"run")
	for action in PAD_BUTTONS:
		if not InputMap.has_action(action):
			continue
		for b in PAD_BUTTONS[action]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)
	for action in PAD_AXES:
		if not InputMap.has_action(action):
			continue
		var a := InputEventJoypadMotion.new()
		a.axis = PAD_AXES[action][0]
		a.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, a)

static func toggle_fullscreen() -> void:
	var w := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if w == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
