extends Node
## Audio: pooled one-shot effects, music, and looping engine voices whose
## pitch/volume follow each kart (cheap on mobile, no runtime synthesis).

const POOL := 12

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _sfx_bus := 0
var _music_bus := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	apply_volumes()


func _ensure_buses() -> void:
	for name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Master")
	_sfx_bus = AudioServer.get_bus_index("SFX")
	_music_bus = AudioServer.get_bus_index("Music")


func apply_volumes() -> void:
	if not has_node("/root/Game"):
		return
	var s: Dictionary = get_node("/root/Game").settings
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(float(s["vol_sfx"]), 0.0001)))
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(float(s["vol_music"]), 0.0001)))


func stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := "res://audio/%s.wav" % name
		var ogg := "res://audio/%s.ogg" % name
		if ResourceLoader.exists(ogg):
			_streams[name] = load(ogg)
		elif ResourceLoader.exists(path):
			_streams[name] = load(path)
		else:
			_streams[name] = null
	return _streams[name]


func play(name: String, _pos = null, pitch := 1.0, volume_db := 0.0) -> void:
	var s := stream(name)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.volume_db = volume_db
	p.play()


func play_music(name: String) -> void:
	var s := stream(name)
	if s == null:
		return
	if _music.stream == s and _music.playing:
		return
	_music.stream = s
	_music.play()


func stop_music() -> void:
	_music.stop()


func make_engine_voice(parent: Node3D, is_player: bool) -> AudioStreamPlayer3D:
	var s := stream("engine_loop")
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.unit_size = 6.0
	p.max_distance = 70.0
	p.volume_db = -4.0 if is_player else -10.0
	p.autoplay = s != null
	parent.add_child(p)
	return p
