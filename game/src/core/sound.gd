extends Node
## Audio: Music / SFX buses, pooled one-shot players, volume settings persisted in user://settings.cfg.
## Hotkeys: volume_down / volume_up / mute.

signal volume_changed(master: float, muted: bool)

const SETTINGS := "user://settings.cfg"
const SOUND_DIR := "res://assets/sounds/"
const POOL := 12
const STEP := 0.1

var master := 0.3        ## linear 0..1, low by default
var music_volume := 0.6
var sfx_volume := 1.0
var muted := false

var _music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
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
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
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
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.pitch_scale = pitch
	p.play()

func music(sound: String) -> void:
	var s := _stream(sound)
	if s == null or _music.stream == s and _music.playing:
		return
	if s is AudioStreamMP3:
		s.loop = true
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
		master = cf.get_value("audio", "master", master)
		music_volume = cf.get_value("audio", "music", music_volume)
		sfx_volume = cf.get_value("audio", "sfx", sfx_volume)
		muted = cf.get_value("audio", "muted", muted)

func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("audio", "muted", muted)
	cf.save(SETTINGS)
