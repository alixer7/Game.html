extends Node
## Autoload "Sfx": pooled sound effects, looping sounds, music with fade, audio buses.

const DIR := "res://assets/audio/"
const POOL := 16

var _streams: Dictionary = {}
var _pool: Array = []
var _next: int = 0
var _music: AudioStreamPlayer
var _music_name: String = ""
var _music_tween: Tween
var _loops: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	apply_volumes()
	Game.settings_changed.connect(apply_volumes)


func _setup_buses() -> void:
	for n in ["Music", "SFX"]:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, n)
			AudioServer.set_bus_send(idx, "Master")
	var mi: int = AudioServer.get_bus_index("Music")
	if mi >= 0 and AudioServer.get_bus_effect_count(mi) == 0:
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 800.0
		AudioServer.add_bus_effect(mi, lpf)
		AudioServer.set_bus_effect_enabled(mi, 0, false)


func apply_volumes() -> void:
	_set_bus("Music", float(Game.settings.get("music", 0.7)) * 0.8)
	_set_bus("SFX", float(Game.settings.get("sfx", 1.0)))


func _set_bus(bus: String, v: float) -> void:
	var i: int = AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))


func set_muffled(on: bool) -> void:
	var mi: int = AudioServer.get_bus_index("Music")
	if mi >= 0 and AudioServer.get_bus_effect_count(mi) > 0:
		AudioServer.set_bus_effect_enabled(mi, 0, on)


func _stream(snd: String) -> AudioStream:
	if _streams.has(snd):
		return _streams[snd]
	var path: String = DIR + snd + ".wav"
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path)
		if st is AudioStreamWAV and (snd.begins_with("music") or snd == "hover"):
			var w: AudioStreamWAV = st.duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * float(w.mix_rate))
			st = w
	_streams[snd] = st
	return st


func play(snd: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var st: AudioStream = _stream(snd)
	if st == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = st
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func loop_start(snd: String, vol_db: float = -6.0) -> void:
	var p: AudioStreamPlayer = _loops.get(snd)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = _stream(snd)
		add_child(p)
		_loops[snd] = p
	if not p.playing:
		p.volume_db = vol_db
		p.play()


func loop_stop(snd: String) -> void:
	var p: AudioStreamPlayer = _loops.get(snd)
	if p != null and p.playing:
		p.stop()


func play_music(snd: String) -> void:
	if snd == _music_name and _music.playing:
		return
	_music_name = snd
	var st: AudioStream = _stream(snd)
	if st == null:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	if _music.playing:
		_music_tween.tween_property(_music, "volume_db", -40.0, 0.4)
	_music_tween.tween_callback(_start_music.bind(st))
	_music_tween.tween_property(_music, "volume_db", 0.0, 1.2)


func _start_music(st: AudioStream) -> void:
	_music.stream = st
	_music.volume_db = -40.0
	_music.play()


func stop_music() -> void:
	_music_name = ""
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -40.0, 0.5)
	_music_tween.tween_callback(_music.stop)
