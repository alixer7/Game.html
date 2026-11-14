extends Node
## Sound manager: one-shot 2D/3D sounds from a pool plus looping channels.

const SOUNDS := ["hit_soft", "hit_hard", "bounce", "jump", "flip", "land", "boost_loop",
	"engine_loop", "pad_small", "pad_big", "goal", "demo", "bump", "beep", "beep_go",
	"crowd_loop", "cheer", "horn", "click", "whoosh", "supersonic", "music_loop"]

var streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _crowd_target := -14.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("SFX")
	_ensure_bus("Music")
	Settings.apply_runtime()
	for s in SOUNDS:
		var path := "res://assets/sfx/%s.wav" % s
		if ResourceLoader.exists(path):
			streams[s] = load(path)
	for i in range(14):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in range(14):
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 14.0
		p3.max_distance = 140.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool3d.append(p3)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_crowd = AudioStreamPlayer.new()
	_crowd.bus = "SFX"
	add_child(_crowd)


func _ensure_bus(nm: String) -> void:
	if AudioServer.get_bus_index(nm) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, nm)
	AudioServer.set_bus_send(idx, "Master")


func has(nm: String) -> bool:
	return streams.has(nm)


func play(nm: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(nm):
		return
	var best: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			best = p
			break
	if best == null:
		best = _pool[randi() % _pool.size()]
	best.stream = streams[nm]
	best.volume_db = volume_db
	best.pitch_scale = pitch
	best.play()


func play_at(nm: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(nm):
		return
	var best: AudioStreamPlayer3D = null
	for p in _pool3d:
		if not p.playing:
			best = p
			break
	if best == null:
		best = _pool3d[randi() % _pool3d.size()]
	best.stream = streams[nm]
	best.volume_db = volume_db
	best.pitch_scale = pitch
	best.global_position = pos
	best.play()


func make_loop_player(nm: String, parent: Node, positional: bool) -> Node:
	if not streams.has(nm):
		return null
	var p: Node
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 10.0
		p3.max_distance = 90.0
		p3.stream = streams[nm]
		p3.bus = "SFX"
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = streams[nm]
		p2.bus = "SFX"
		p = p2
	parent.add_child(p)
	return p


func play_music(on: bool) -> void:
	if not streams.has("music_loop"):
		return
	if on and not _music.playing:
		_music.stream = streams["music_loop"]
		_music.volume_db = -6.0
		_music.play()
	elif not on and _music.playing:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -40.0, 0.8)
		tw.tween_callback(_music.stop)


func crowd(on: bool, level_db: float = -14.0) -> void:
	if not streams.has("crowd_loop"):
		return
	_crowd_target = level_db
	if on and not _crowd.playing:
		_crowd.stream = streams["crowd_loop"]
		_crowd.volume_db = -40.0
		_crowd.play()
	elif not on:
		_crowd_target = -60.0


func _process(delta: float) -> void:
	if _crowd.playing:
		_crowd.volume_db = move_toward(_crowd.volume_db, _crowd_target, delta * 20.0)
		if _crowd_target <= -59.0 and _crowd.volume_db <= -58.0:
			_crowd.stop()


func crowd_swell(extra_db: float, _seconds: float) -> void:
	if _crowd.playing:
		_crowd.volume_db = maxf(_crowd.volume_db, _crowd_target + extra_db)
