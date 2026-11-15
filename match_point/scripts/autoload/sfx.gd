extends Node
## مدير الأصوات (يُستكمل في خطوة الصوت)

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _crowd: AudioStreamPlayer
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_crowd = AudioStreamPlayer.new()
	add_child(_crowd)
	_load_all()


func _load_all() -> void:
	var dir := DirAccess.open("res://assets/audio")
	if dir == null:
		return
	for f in dir.get_files():
		var name := f
		if name.ends_with(".import"):
			name = name.trim_suffix(".import")
		if name.ends_with(".wav") or name.ends_with(".ogg"):
			var key := name.get_basename()
			if not _streams.has(key) and ResourceLoader.exists("res://assets/audio/" + name):
				_streams[key] = load("res://assets/audio/" + name)


func play(key: String, volume: float = 1.0, pitch: float = 1.0) -> void:
	if not enabled or not _streams.has(key):
		return
	var v: float = float(Settings.get_v("sfx")) * volume
	if v <= 0.001:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.volume_db = linear_to_db(clampf(v, 0.0, 1.5))
	p.pitch_scale = pitch
	p.play()


func play_crowd(key: String, volume: float = 1.0) -> void:
	if not enabled or not _streams.has(key):
		return
	var v: float = float(Settings.get_v("crowd")) * volume
	if v <= 0.001:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.volume_db = linear_to_db(clampf(v, 0.0, 1.5))
	p.pitch_scale = 1.0
	p.play()


func ambience(on: bool) -> void:
	if not _streams.has("crowd_ambience"):
		return
	if on and enabled:
		if not _crowd.playing:
			var st: AudioStream = _streams["crowd_ambience"]
			if st is AudioStreamWAV:
				var w := st as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				w.loop_end = int(w.get_length() * w.mix_rate)
			_crowd.stream = st
			_crowd.volume_db = linear_to_db(maxf(float(Settings.get_v("crowd")) * 0.5, 0.0001))
			_crowd.play()
	else:
		_crowd.stop()


func refresh_volume() -> void:
	if _crowd.playing:
		_crowd.volume_db = linear_to_db(maxf(float(Settings.get_v("crowd")) * 0.5, 0.0001))
