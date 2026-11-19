class_name Sfx
extends Node
## Procedural sound synthesiser: every sound in the game is generated here at
## start-up (engines, tyres, wind, crashes, sirens, UI), so no audio assets are needed.

const SR := 22050
var cache := {}
var _rng := RandomNumberGenerator.new()
var ui_player: AudioStreamPlayer


func _ready() -> void:
	_rng.seed = 7
	ui_player = AudioStreamPlayer.new()
	ui_player.bus = "Master"
	add_child(ui_player)


func get_sound(key: String) -> AudioStreamWAV:
	if cache.has(key):
		return cache[key]
	var s: AudioStreamWAV
	var parts := key.split(":")
	match parts[0]:
		"engine":
			s = _engine(int(parts[1]), parts[2] == "on")
		"squeal":
			s = _squeal()
		"gravel":
			s = _gravel()
		"wind":
			s = _wind()
		"crash":
			s = _crash(int(parts[1]))
		"scrape":
			s = _scrape()
		"nitro":
			s = _nitro()
		"siren":
			s = _siren()
		"beep":
			s = _tone(float(parts[1]), 0.22, 0.6)
		"chime":
			s = _chime()
		"pop":
			s = _pop()
		"horn":
			s = _horn()
		"click":
			s = _tone(1400.0, 0.04, 0.35)
		"whoosh":
			s = _whoosh()
		"thud":
			s = _thud()
		_:
			s = _tone(440.0, 0.1, 0.3)
	cache[key] = s
	return s


func play_ui(key: String, vol_db := -6.0) -> void:
	ui_player.stream = get_sound(key)
	ui_player.volume_db = vol_db
	ui_player.play()


# --------------------------------------------------------------------------- helpers
func _make(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := samples.size()
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, absf(samples[i]))
	var gain := 0.92 / peak
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0


## crossfade the tail into the head so noise loops are seamless
func _seam(buf: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := buf.size()
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in n - fade:
		out[i] = buf[i]
	for i in fade:
		var t := float(i) / fade
		out[i] = buf[i] * t + buf[n - fade + i] * (1.0 - t)
	return out


# --------------------------------------------------------------------------- engines
## Engine loop recorded at 2000 rpm (pitch_scale = rpm / 2000 at playback).
func _engine(cyl: int, on: bool) -> AudioStreamWAV:
	var rpm := 2000.0
	var firing := rpm / 60.0 * cyl * 0.5
	var cycle_len := int(round(SR / (rpm / 120.0)))  # one 4-stroke cycle (2 crank revs)
	var cycles := 14
	var n := cycle_len * cycles
	var buf := PackedFloat32Array()
	buf.resize(n)
	var pulse_len := float(cycle_len) / cyl
	var amps := []
	var rng := RandomNumberGenerator.new()
	rng.seed = cyl * 31 + (1 if on else 0)
	for c in cyl:
		amps.append(rng.randf_range(0.75, 1.0) if cyl != 8 else (1.0 if c % 2 == 0 else 0.72))
	var res_f := firing * (3.2 if on else 2.2)
	var tau := (0.35 if on else 0.22) * pulse_len / SR
	var lp := 0.0
	var lp2 := 0.0
	var a_lp := 0.55 if on else 0.32
	for i in n:
		var pos := i % cycle_len
		var k := int(pos / pulse_len)
		var t := (pos - k * pulse_len) / SR
		var p: float = amps[k % cyl] * exp(-t / tau) * sin(TAU * res_f * t)
		# low rumble at firing frequency and half order (uneven firing burble)
		var ph := float(i) / SR
		p += 0.55 * sin(TAU * firing * ph) + 0.35 * sin(TAU * firing * 0.5 * ph) * (0.6 if cyl == 8 else 0.25)
		p += _noise() * (0.18 if on else 0.08) * exp(-t / (tau * 2.0))
		lp += (p - lp) * a_lp
		lp2 += (lp - lp2) * a_lp
		buf[i] = lp2
	# remove DC
	var mean := 0.0
	for i in n:
		mean += buf[i]
	mean /= n
	for i in n:
		buf[i] -= mean
	return _make(buf, true)


func _squeal() -> AudioStreamWAV:
	var n := SR
	var buf := PackedFloat32Array()
	buf.resize(n + 2000)
	var bp1 := 0.0
	var bp2 := 0.0
	var f := 1050.0
	var q := 0.08
	for i in buf.size():
		var t := float(i) / SR
		var x := _noise()
		var fm := f * (1.0 + 0.06 * sin(TAU * 7.0 * t) + 0.03 * sin(TAU * 13.0 * t))
		var w := 2.0 * sin(PI * fm / SR)
		bp1 += w * (x - bp1 - q * bp2)
		bp2 += w * bp1
		buf[i] = bp2 * 0.6 + sin(TAU * fm * t) * 0.25
	return _make(_seam(buf, 2000), true)


func _gravel() -> AudioStreamWAV:
	var n := SR + 2000
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var env := 0.0
	for i in n:
		if _rng.randf() < 0.012:
			env = _rng.randf_range(0.4, 1.0)
		env *= 0.9975
		var x := _noise() * (0.25 + env)
		lp += (x - lp) * 0.35
		buf[i] = lp
	return _make(_seam(buf, 2000), true)


func _wind() -> AudioStreamWAV:
	var n := SR * 2 + 4000
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (_noise() - lp) * (0.05 + 0.03 * sin(TAU * 0.5 * t))
		lp2 += (lp - lp2) * 0.2
		buf[i] = lp2
	return _make(_seam(buf, 4000), true)


func _scrape() -> AudioStreamWAV:
	var n := SR + 2000
	var buf := PackedFloat32Array()
	buf.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / SR
		var x := _noise() * (0.6 + 0.4 * sin(TAU * 31.0 * t))
		hp = 0.7 * (hp + x - prev)
		prev = x
		buf[i] = hp + sin(TAU * 2300.0 * t) * 0.15 * (0.5 + 0.5 * sin(TAU * 11.0 * t))
	return _make(_seam(buf, 2000), true)


func _nitro() -> AudioStreamWAV:
	var n := SR + 3000
	var buf := PackedFloat32Array()
	buf.resize(n)
	var bp1 := 0.0
	var bp2 := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var x := _noise()
		var w := 2.0 * sin(PI * 1800.0 / SR)
		bp1 += w * (x - bp1 - 0.6 * bp2)
		bp2 += w * bp1
		lp += (x - lp) * 0.04
		buf[i] = bp2 * 0.4 + lp * 2.0 + sin(TAU * 55.0 * t) * 0.2
	return _make(_seam(buf, 3000), true)


func _siren() -> AudioStreamWAV:
	var period := 3.6
	var n := int(SR * period)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := 980.0 + 380.0 * sin(TAU * t / period - PI * 0.5)
		ph += TAU * f / SR
		var s := sin(ph) + 0.3 * sin(ph * 2.0) + 0.15 * sin(ph * 3.0)
		buf[i] = s
	return _make(buf, true)


# --------------------------------------------------------------------------- one-shots
func _crash(variant: int) -> AudioStreamWAV:
	var n := int(SR * 1.1)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var partials := []
	for k in 7:
		partials.append([rng.randf_range(180.0, 2400.0), rng.randf_range(0.08, 0.5), rng.randf_range(0.2, 1.0)])
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 7.0)
		var x := _noise() * env
		lp += (x - lp) * 0.3
		var s := lp * 1.4 + x * 0.3
		for p in partials:
			s += sin(TAU * float(p[0]) * t) * exp(-t / float(p[1])) * float(p[2]) * 0.25
		# low thump
		s += sin(TAU * 60.0 * t) * exp(-t * 14.0) * 1.2
		buf[i] = s
	return _make(buf, false)


func _thud() -> AudioStreamWAV:
	var n := int(SR * 0.35)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (_noise() * exp(-t * 25.0) - lp) * 0.15
		buf[i] = lp + sin(TAU * 70.0 * t) * exp(-t * 18.0)
	return _make(buf, false)


func _tone(f: float, dur: float, decay: float) -> AudioStreamWAV:
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var env := minf(t * 200.0, 1.0) * exp(-t / maxf(decay * dur, 0.001))
		buf[i] = (sin(TAU * f * t) + 0.2 * sin(TAU * f * 2.0 * t)) * env
	return _make(buf, false)


func _chime() -> AudioStreamWAV:
	var n := int(SR * 0.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var a := sin(TAU * 988.0 * t) * exp(-t * 6.0)
		var b := sin(TAU * 1480.0 * t) * exp(-maxf(t - 0.09, 0.0) * 5.0) * (1.0 if t > 0.09 else 0.0)
		buf[i] = a + b
	return _make(buf, false)


func _pop() -> AudioStreamWAV:
	var n := int(SR * 0.25)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (_noise() - lp) * 0.25
		buf[i] = lp * exp(-t * 30.0) + sin(TAU * 90.0 * t) * exp(-t * 40.0)
	return _make(buf, false)


func _horn() -> AudioStreamWAV:
	var n := int(SR * 0.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var env := minf(t * 60.0, 1.0) * minf((0.6 - t) * 30.0, 1.0)
		var s := 0.0
		for f: float in [415.0, 520.0]:
			var ph: float = TAU * f * t
			s += sin(ph) + 0.5 * sin(ph * 2.0) + 0.3 * sin(ph * 3.0)
		buf[i] = s * env
	return _make(buf, false)


func _whoosh() -> AudioStreamWAV:
	var n := int(SR * 0.7)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var env := sin(PI * t / 0.7)
		lp += (_noise() - lp) * (0.05 + 0.25 * env)
		buf[i] = lp * env
	return _make(buf, false)
