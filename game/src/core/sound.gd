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
var _amb: AudioStreamPlayer
const VOICES := 24         ## copies of one effect at once (AudioStreamPlayer.max_polyphony: the oldest gives way)
const DUCK_TIME := 0.03    ## seconds for overlapping copies to ease to their shared level

const UI_GAP_MS := 150      ## interface sounds closer than this are one action

var _ui_at := -100000
var _players := {}   ## "sound|spread|db" -> its AudioStreamPlayer (one per effect, polyphonic)
var _ends := {}      ## same key -> when each playing copy ends (ticks msec)
var _frame_of := {}  ## same key -> the engine frame it last started in
var _cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "SFX"
	add_child(_amb)
	_load_settings()
	Feel.load_settings()
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
		_cache[sound] = null
		for ext in [".ogg", ".mp3"]:   # remastered files are .ogg; the rest are the original .mp3
			if ResourceLoader.exists(SOUND_DIR + sound + ext):
				_cache[sound] = load(SOUND_DIR + sound + ext)
				break
		if _cache[sound] == null:
			push_warning("missing sound " + sound)
	return _cache[sound]

## Play a one-shot effect by file name (without extension). spread > 0: a random pitch within ±spread each time
## (AudioStreamRandomizer), so a move repeated in a combo does not sound mechanical.
## Every request plays to its end, so rapid hits (a held 冰龙波 on a crowd) are all heard; overlapping copies share a
## level (_share, eased in _process): a crowd of hits is a little louder than one, not n times; the SFX bus ends in a
## limiter. Requests in one frame are one sound: the same blow on several enemies at once.
func sfx(sound: String, spread := 0.0, volume_db := 0.0) -> void:
	var s := _stream(sound)
	if s == null:
		return
	var key := "%s|%s|%s" % [sound, spread, volume_db]
	var frame := Engine.get_process_frames()
	if _frame_of.get(key, -1) == frame:
		return
	_frame_of[key] = frame
	var p: AudioStreamPlayer = _players.get(key)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.max_polyphony = VOICES
		if spread > 0.0:
			var r := AudioStreamRandomizer.new()
			r.add_stream(0, s)
			r.random_pitch = 1.0 + spread
			p.stream = r
		else:
			p.stream = s
		p.set_meta(&"gain", db_to_linear(volume_db))
		add_child(p)
		_players[key] = p
	var now := Time.get_ticks_msec()
	var ends: Array = _ends.get(key, []).filter(func(e: int) -> bool: return e > now)
	if ends.size() >= VOICES:
		ends.pop_front()
	ends.append(now + int(s.get_length() * (1.0 + spread) * 1000.0))
	_ends[key] = ends
	var level: float = _share(ends.size()) * p.get_meta(&"gain")
	p.volume_linear = minf(p.volume_linear, level) if ends.size() > 1 else level
	p.play()

## An interface sound: one per player action - a click that opens a panel is one sound, not a click plus an open.
## (ui_click is the generic one; SD_xz the original 选择.)
func ui(sound := "ui_click") -> void:
	var now := Time.get_ticks_msec()
	if now - _ui_at < UI_GAP_MS:
		return
	_ui_at = now
	sfx(sound)

## Level of each of n overlapping copies of one effect. Measured on the hit sounds (ffmpeg, EBU R128 momentary max,
## copies 50-100 ms apart, no attenuation): n copies are 10*log10(n) dB louder than one (2: +3 dB, 4: +6, 8: +9), the sum
## of uncorrelated sounds. n^-1/4 each halves that rise: 2 copies +1.5 dB, 4: +3, 8: +4.5 - a crowd of hits is louder
## than one, without the roar. The SFX bus limiter keeps the peaks under 0 dBFS.
static func _share(n: int) -> float:
	return pow(float(n), -0.25)

## Overlapping copies of an effect ease towards _share(n) each (n = copies playing).
func _process(delta: float) -> void:
	var k := minf(delta / DUCK_TIME, 1.0)
	var now := Time.get_ticks_msec()
	for key in _ends:
		var ends: Array = _ends[key].filter(func(e: int) -> bool: return e > now)
		_ends[key] = ends
		if not ends.is_empty():
			var p: AudioStreamPlayer = _players[key]
			p.volume_linear = lerpf(p.volume_linear, _share(ends.size()) * float(p.get_meta(&"gain")), k)

## loop: false for jingles (the game-over tune plays once).
func music(sound: String, loop := true) -> void:
	var s := _stream(sound)
	if s == null or _music.stream == s and _music.playing:
		return
	if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = loop
	_music.stream = s
	_music.play()

func stop_music() -> void:
	_music.stop()

## A quiet looping background sound of the stage (rain, river, fire...; "" = none). Plays on the SFX bus.
func ambience(sound: String, volume_db := -18.0) -> void:
	var s := _stream(sound)
	if s == null:
		_amb.stop()
		_amb.stream = null
		return
	if _amb.stream == s and _amb.playing:
		_amb.volume_db = volume_db
		return
	if s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.loop = true
	_amb.stream = s
	_amb.volume_db = volume_db
	_amb.play()

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
