extends Node
## Audio: Music / SFX buses (default_bus_layout.tres: the web build only plays on buses declared there), pooled one-shot players, volume settings persisted in user://settings.cfg.
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
const VOICES := 8          ## at most this many copies of one effect at once; more requests are dropped, none is cut
const MIN_GAP := 0.045     ## seconds: the same effect asked again sooner is one sound (a blow on several enemies)

var _players := {}   ## sound -> its AudioStreamPlayers, one per playing copy
var _last_at := {}   ## sound -> time (s) it last started
var _cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	if sound == "":   # an action without a sound
		return null
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
	# A blow landing on several enemies asks once per enemy: requests close together are one sound (stacked copies were
	# a roar). Every copy plays to its end on its own player: when all VOICES are busy the new request is dropped
	# instead of cutting one that is still playing (a held 冰龙波 hitting a crowd stuttered).
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_at.get(sound, -100.0)) < MIN_GAP:
		return
	var pool: Array = _players.get(sound, [])
	_players[sound] = pool
	var p: AudioStreamPlayer = null
	for q: AudioStreamPlayer in pool:
		if not q.playing:
			p = q
			break
	if p == null:
		if pool.size() >= VOICES:
			return
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = s
		add_child(p)
		pool.append(p)
	_last_at[sound] = now
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

## Re-applies the bus volumes and mute (also when the web page hides or shows the game).
func apply() -> void:
	_apply()

func _apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(master))
	AudioServer.set_bus_mute(0, muted or master <= 0.0 or WebHost.hidden)
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
