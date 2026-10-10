extends Node
## Audio: Music / SFX buses, pooled one-shot players, volume settings persisted in user://settings.cfg.
## Hotkeys: volume_down / volume_up / mute.

signal volume_changed(master: float, muted: bool)

const SETTINGS := "user://settings.cfg"
const SOUND_DIR := "res://assets/sounds/"
const STEP := 0.1

var master := 0.3        ## linear 0..1, low by default
var music_volume := 0.6
var sfx_volume := 1.0
var muted := false

var _music: AudioStreamPlayer
var _players := {}   ## sound -> its AudioStreamPlayer (a few overlapping plays allowed: a new one never cuts the old)
var _frame_of := {}  ## sound -> the engine frame it last started in
var _cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_load_settings()
	_apply()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("volume_down"):
		set_master(master - STEP)
	elif e.is_action_pressed("volume_up"):
		set_master(master + STEP)
	elif e.is_action_pressed("mute"):
		set_muted(not muted)

func _stream(sound: String) -> AudioStream:
	if not _cache.has(sound):
		var path := SOUND_DIR + sound + ".mp3"
		_cache[sound] = load(path) if ResourceLoader.exists(path) else null
		if _cache[sound] == null:
			push_warning("missing sound " + sound)
	return _cache[sound]

## Play a one-shot effect by file name (without extension).
func sfx(sound: String, pitch := 1.0) -> void:
	var s := _stream(sound)
	if s == null:
		return
	# The same effect asked for again in the same frame is one sound: a blow landing on several enemies asks once per
	# enemy, and stacked copies were a roar (the original did stack them). Later requests overlap normally.
	var frame := Engine.get_process_frames()
	if _frame_of.get(sound, -1) == frame:
		return
	_frame_of[sound] = frame
	var p: AudioStreamPlayer = _players.get(sound)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = s
		p.max_polyphony = 6   # the engine mixes overlapping plays of one player; none is cut until six are running
		add_child(p)
		_players[sound] = p
	p.pitch_scale = pitch
	p.play()

## loop: false for jingles (the game-over tune plays once).
func music(sound: String, loop := true) -> void:
	var s := _stream(sound)
	if s == null or _music.stream == s and _music.playing:
		return
	if s is AudioStreamMP3:
		s.loop = loop
	_music.stream = s
	_music.play()

func stop_music() -> void:
	_music.stop()

func set_master(v: float) -> void:
	master = clampf(snappedf(v, 0.01), 0.0, 1.0)
	muted = false
	_apply()
	_save_settings()

func set_muted(v: bool) -> void:
	muted = v
	_apply()
	_save_settings()

func _apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(master))
	AudioServer.set_bus_mute(0, muted or master <= 0.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(music_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx_volume))
	volume_changed.emit(master, muted)

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		master = _volume(cf.get_value("audio", "master", master), master)
		music_volume = _volume(cf.get_value("audio", "music", music_volume), music_volume)
		sfx_volume = _volume(cf.get_value("audio", "sfx", sfx_volume), sfx_volume)
		muted = cf.get_value("audio", "muted", muted) == true

static func _volume(v: Variant, fallback: float) -> float:
	return clampf(float(v), 0.0, 1.0) if v is float or v is int else fallback

func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("audio", "muted", muted)
	if cf.save(SETTINGS) != OK:
		push_warning("settings could not be saved")
