extends Node
## مولّد أصوات إجرائي: كل الأصوات تُصنع برمجياً عند بدء اللعبة (بدون ملفات صوتية).

const RATE := 16000

var streams := {}
var _pool3d: Array = []
var _pool2d: Array = []
var _loops := {}
var _ready_flag := false
var _task := -1
var _gen_result := {}
var _mutex := Mutex.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(14):
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 60.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	for i in range(6):
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool2d.append(p2)
	_task = WorkerThreadPool.add_task(_generate_all, false, "sfx_gen")

func _process(_dt: float) -> void:
	if not _ready_flag and _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_mutex.lock()
		for k in _gen_result:
			streams[k] = _to_wav(_gen_result[k]["s"], _gen_result[k]["loop"])
		_gen_result.clear()
		_mutex.unlock()
		_ready_flag = true
		for name in _loops:
			_loops[name]["player"].stream = streams.get(name)
			if _loops[name]["target"] > 0.001:
				_loops[name]["player"].play()
	for name in _loops:
		var L: Dictionary = _loops[name]
		var p: AudioStreamPlayer = L["player"]
		L["cur"] = move_toward(L["cur"], L["target"], _dt * 0.6)
		p.volume_db = linear_to_db(max(L["cur"], 0.0001))
		if L["cur"] <= 0.001 and p.playing:
			p.stop()
		elif L["cur"] > 0.001 and not p.playing and _ready_flag:
			p.play()

func play(name: String, pos = null, vol_db := 0.0, pitch_var := 0.12) -> void:
	if not _ready_flag or not streams.has(name):
		return
	if pos is Vector3:
		for p in _pool3d:
			if not p.playing:
				p.stream = streams[name]
				p.global_position = pos
				p.volume_db = vol_db
				p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
				p.play()
				return
	else:
		for p in _pool2d:
			if not p.playing:
				p.stream = streams[name]
				p.volume_db = vol_db
				p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
				p.play()
				return

func set_loop(name: String, volume: float) -> void:
	if not _loops.has(name):
		var p := AudioStreamPlayer.new()
		add_child(p)
		if _ready_flag:
			p.stream = streams.get(name)
		_loops[name] = {"player": p, "cur": 0.0, "target": 0.0}
	_loops[name]["target"] = clampf(volume, 0.0, 1.0)

func stop_all_loops() -> void:
	for name in _loops:
		_loops[name]["target"] = 0.0

# ------------------------------------------------------------------
func _to_wav(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in range(s.size()):
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w

func _generate_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var out := {}
	out["chop"] = {"s": _thump(rng, 0.2, 150.0, 0.9, 0.5), "loop": false}
	out["build"] = {"s": _thump(rng, 0.16, 210.0, 0.8, 0.7), "loop": false}
	out["hit"] = {"s": _thump(rng, 0.12, 90.0, 0.7, 0.9), "loop": false}
	out["mine"] = {"s": _clink(rng, 0.25, [1250.0, 1870.0, 2630.0]), "loop": false}
	out["craft"] = {"s": _clink(rng, 0.18, [900.0, 1400.0]), "loop": false}
	out["pickup"] = {"s": _sweep(0.11, 600.0, 1150.0, 0.5), "loop": false}
	out["click"] = {"s": _sweep(0.035, 1800.0, 1400.0, 0.35), "loop": false}
	out["hurt"] = {"s": _grunt(rng, 0.3, 170.0), "loop": false}
	out["eat"] = {"s": _crunch(rng, 0.45), "loop": false}
	out["drink"] = {"s": _gulp(0.4), "loop": false}
	out["step"] = {"s": _noise_burst(rng, 0.07, 0.15, 0.35), "loop": false}
	out["splash"] = {"s": _noise_burst(rng, 0.45, 0.5, 0.6), "loop": false}
	out["thunder"] = {"s": _rumble(rng, 2.6), "loop": false}
	out["bow"] = {"s": _sweep(0.25, 260.0, 160.0, 0.6), "loop": false}
	out["howl"] = {"s": _howl(1.9), "loop": false}
	out["growl"] = {"s": _growl(rng, 0.7), "loop": false}
	out["fall"] = {"s": _rumble(rng, 1.1), "loop": false}
	out["levelup"] = {"s": _arp([523.0, 659.0, 784.0, 1046.0], 0.09), "loop": false}
	out["coin"] = {"s": _clink(rng, 0.2, [2100.0, 3150.0]), "loop": false}
	out["wind"] = {"s": _loop_noise(rng, 3.0, 0.02, 0.5), "loop": true}
	out["rain"] = {"s": _loop_noise(rng, 2.0, 0.55, 0.32), "loop": true}
	out["fire"] = {"s": _fire(rng, 2.0), "loop": true}
	out["birds"] = {"s": _birds(rng, 5.0), "loop": true}
	out["crickets"] = {"s": _crickets(rng, 2.0), "loop": true}
	_mutex.lock()
	_gen_result = out
	_mutex.unlock()

func _env(i: int, n: int, attack := 0.01) -> float:
	var t := float(i) / RATE
	var dur := float(n) / RATE
	var a := clampf(t / attack, 0.0, 1.0)
	return a * pow(1.0 - t / dur, 2.0)

func _thump(rng: RandomNumberGenerator, dur: float, freq: float, noise_amt: float, tone_amt: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var f := freq * (1.0 - t / dur * 0.5)
		ph += TAU * f / RATE
		lp += 0.25 * (rng.randf_range(-1, 1) - lp)
		s[i] = (sin(ph) * tone_amt + lp * noise_amt * 2.0) * _env(i, n, 0.002) * 0.8
	return s

func _clink(rng: RandomNumberGenerator, dur: float, freqs: Array) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.0
		for k in range(freqs.size()):
			v += sin(TAU * freqs[k] * t) * exp(-t * (14.0 + k * 6.0)) / (k + 1)
		v += rng.randf_range(-1, 1) * exp(-t * 60.0) * 0.4
		s[i] = v * 0.5
	return s

func _sweep(dur: float, f0: float, f1: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in range(n):
		var k := float(i) / n
		ph += TAU * lerpf(f0, f1, k) / RATE
		s[i] = sin(ph) * amp * _env(i, n, 0.004)
	return s

func _arp(freqs: Array, step: float) -> PackedFloat32Array:
	var n := int(step * freqs.size() * RATE + RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.0
		for k in range(freqs.size()):
			var t0: float = k * step
			if t >= t0:
				v += sin(TAU * freqs[k] * (t - t0)) * exp(-(t - t0) * 6.0)
		s[i] = v * 0.25
	return s

func _grunt(rng: RandomNumberGenerator, dur: float, freq: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / RATE
		ph += TAU * freq * (1.0 + 0.1 * sin(t * 40.0)) * (1.0 - t * 0.8) / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		s[i] = (saw * 0.5 + rng.randf_range(-0.2, 0.2)) * _env(i, n, 0.02) * 0.7
	return s

func _crunch(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var pulse := maxf(0.0, sin(t * TAU * 7.0))
		s[i] = rng.randf_range(-1, 1) * pow(pulse, 6.0) * 0.5 * (1.0 - t / dur)
	return s

func _gulp(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var local := fmod(t, 0.2) / 0.2
		ph += TAU * lerpf(180.0, 420.0, local) / RATE
		s[i] = sin(ph) * sin(local * PI) * 0.45
	return s

func _noise_burst(rng: RandomNumberGenerator, dur: float, cutoff: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in range(n):
		lp += cutoff * (rng.randf_range(-1, 1) - lp)
		s[i] = lp * amp * 2.5 * _env(i, n, 0.003)
	return s

func _rumble(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var b := 0.0
	for i in range(n):
		var t := float(i) / RATE
		b = b * 0.995 + rng.randf_range(-1, 1) * 0.06
		var crack := rng.randf_range(-1, 1) * exp(-t * 8.0) * 0.4
		s[i] = (b * 2.2 + crack) * _env(i, n, 0.03) * (0.7 + 0.3 * sin(t * 9.0))
	return s

func _howl(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in range(n):
		var k := float(i) / n
		var f := 380.0 + sin(k * PI) * 320.0 + sin(k * 60.0) * 8.0
		ph += TAU * f / RATE
		s[i] = (sin(ph) + 0.3 * sin(ph * 2.0)) * sin(k * PI) * 0.3
	return s

func _growl(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / RATE
		lp += 0.08 * (rng.randf_range(-1, 1) - lp)
		s[i] = lp * 4.0 * (0.6 + 0.4 * sin(t * TAU * 28.0)) * _env(i, n, 0.05)
	return s

func _loop_noise(rng: RandomNumberGenerator, dur: float, cutoff: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(n):
		lp += cutoff * (rng.randf_range(-1, 1) - lp)
		lp2 += 0.0008 * (rng.randf_range(-1, 1) - lp2)
		var mod := 0.7 + clampf(lp2 * 30.0, -0.3, 0.3)
		s[i] = lp * amp * mod * (3.0 if cutoff < 0.1 else 1.0)
	# مزج الطرفين لحلقة سلسة
	var fade := int(0.25 * RATE)
	for i in range(fade):
		var k := float(i) / fade
		s[i] = s[i] * k + s[n - fade + i] * (1.0 - k)
	s.resize(n - fade)
	return s

func _fire(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var s := _loop_noise(rng, dur, 0.05, 0.25)
	for c in range(int(dur * 25)):
		var at := rng.randi_range(0, s.size() - 200)
		var amp := rng.randf_range(0.2, 0.7)
		for j in range(120):
			s[at + j] += rng.randf_range(-1, 1) * amp * exp(-j / 18.0)
	return s

func _birds(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for c in range(9):
		var at := rng.randi_range(0, n - RATE / 2)
		var f0 := rng.randf_range(2200.0, 3800.0)
		var notes := rng.randi_range(2, 5)
		for k in range(notes):
			var len_s := int(rng.randf_range(0.05, 0.12) * RATE)
			var st := at + k * int(0.13 * RATE)
			var ph := 0.0
			for j in range(len_s):
				if st + j >= n:
					break
				var q := float(j) / len_s
				ph += TAU * (f0 + sin(q * PI) * 700.0 - k * 120.0) / RATE
				s[st + j] += sin(ph) * sin(q * PI) * 0.12
	return s

func _crickets(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var chirp := maxf(0.0, sin(t * TAU * 3.0))
		var pulse := maxf(0.0, sin(t * TAU * 45.0))
		s[i] = sin(t * TAU * 4400.0) * pow(chirp, 8.0) * pulse * 0.08
	return s
