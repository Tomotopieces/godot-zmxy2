class_name Feel
extends RefCounted
## Game-feel switches and the gamepad rumble.
## screen_shake / pad_rumble are player settings (pause menu, saved in user://settings.cfg [feel]);
## hero_hurt_stop is a debug switch (key 8): the hero and a melee attacker freeze briefly when the hero is hit.

const SETTINGS := "user://settings.cfg"

static var screen_shake := true
static var pad_rumble := true
static var hero_hurt_stop := false
static var hitstop_on := true   ## off for frame-exact test runs (tools/ai_trace)

static func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		screen_shake = cf.get_value("feel", "screen_shake", screen_shake) == true
		pad_rumble = cf.get_value("feel", "pad_rumble", pad_rumble) == true

static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("feel", "screen_shake", screen_shake)
	cf.set_value("feel", "pad_rumble", pad_rumble)
	if cf.save(SETTINGS) != OK:
		push_warning("settings could not be saved")

## Rumbles every connected pad: strength 0..1 (the heavy motor; the light one at 60 %).
static func rumble(strength: float, seconds: float) -> void:
	if not pad_rumble:
		return
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, strength * 0.6, strength, seconds)
