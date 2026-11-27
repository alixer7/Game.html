extends Node
## Procedural audio (autoload "SFX"). Everything is synthesized at startup on a
## worker thread into AudioStreamWAV buffers: impacts, bone cracks, blood, fire,
## formant-synthesized character voices and looping music layers.

const SR := 22050
const VSR := 16000

var streams := {}       # name -> Array[AudioStreamWAV]
var voices := {}        # "id:kind" -> Array
var players := []
var pi := 0
var music_base: AudioStreamPlayer
var music_drums: AudioStreamPlayer
var music_kind := ""
var music_int := 0.3
var is_ready := false
var thread: Thread
var tts_voice := ""

const VOICE_PROF := {
	vorgath = {f0 = 58.0, fs = 0.62, dist = 9.0, rasp = 1.0},
	nyxara = {f0 = 330.0, fs = 1.25, dist = 0.0, rasp = 0.35},
	kharos = {f0 = 82.0, fs = 0.78, dist = 4.0, rasp = 0.7},
	ossirah = {f0 = 120.0, fs = 0.95, dist = 1.5, rasp = 0.8},
}

func _ready() -> void:
	_buses()
	for i in 22:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	music_base = AudioStreamPlayer.new()
	music_base.bus = "Music"
	add_child(music_base)
	music_drums = AudioStreamPlayer.new()
	music_drums.bus = "Music"
	add_child(music_drums)
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		var vs := DisplayServer.tts_get_voices_for_language("en")
		if vs.size() > 0: tts_voice = vs[0]
	thread = Thread.new()
	thread.start(_generate_all)

func _exit_tree() -> void:
	if thread and thread.is_started(): thread.wait_to_finish()

func _buses() -> void:
	var m := AudioServer.get_bus_index("Master")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -12.0
	comp.ratio = 4.0
	AudioServer.add_bus_effect(m, comp)
	var lim := AudioEffectLimiter.new()
	AudioServer.add_bus_effect(m, lim)
	for b in [["SFX", 0.18, 0.75], ["Music", 0.35, 0.9]]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, b[0])
		AudioServer.set_bus_send(i, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = b[2]
		rv.wet = b[1]
		rv.dry = 1.0
		rv.damping = 0.4
		AudioServer.add_bus_effect(i, rv)
	set_volumes(0.9, 0.55)

func set_volumes(sfx: float, music: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(0.0001, sfx)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.0001, music * 0.7)))

# ================================================================= playback
func play(name: String, power := 1.0) -> void:
	if not streams.has(name): return
	var arr: Array = streams[name]
	if arr.is_empty(): return
	var p: AudioStreamPlayer = players[pi]
	pi = (pi + 1) % players.size()
	p.stream = arr[randi() % arr.size()]
	p.volume_db = linear_to_db(clampf(power * 0.85, 0.05, 1.3))
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()

func voice(id: String, kind: String, power := 1.0) -> void:
	var k := kind
	if k in ["atk2", "taunt"]: k = "atk"
	if k == "grunt": k = "atk" if randf() < 0.5 else "hurt"
	var key := id + ":" + k
	if not voices.has(key): return
	var p: AudioStreamPlayer = players[pi]
	pi = (pi + 1) % players.size()
	p.stream = voices[key][randi() % voices[key].size()]
	p.volume_db = linear_to_db(clampf(power, 0.05, 1.2))
	p.pitch_scale = randf_range(0.94, 1.06) * (1.15 if kind == "grunt" else 1.0)
	p.play()

func say(text: String) -> void:
	if not G.settings.voice or tts_voice == "": return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, tts_voice, 100, 0.25, 0.8)

func start_music(kind: String) -> void:
	if kind == music_kind or not streams.has("music_" + kind): return
	music_kind = kind
	music_base.stream = streams["music_" + kind][0]
	music_base.play()
	if streams.has("drums_" + kind):
		music_drums.stream = streams["drums_" + kind][0]
		music_drums.play()
	else:
		music_drums.stop()

func stop_music() -> void:
	music_kind = ""
	music_base.stop()
	music_drums.stop()

func _process(_dt: float) -> void:
	if music_drums.playing:
		music_drums.volume_db = linear_to_db(clampf(0.25 + music_int, 0.05, 1.2))
	if not music_base.playing and music_kind != "" and streams.has("music_" + music_kind):
		var k := music_kind
		music_kind = ""
		start_music(k)

# ================================================================= synthesis
class BQ extends RefCounted:
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var type := "lp"
	var sr := 22050.0
	func _init(t: String, f: float, q: float, s: float) -> void:
		type = t
		sr = s
		set_f(f, q)
	func set_f(f: float, q: float) -> void:
		f = clampf(f, 20.0, sr * 0.45)
		var w := TAU * f / sr
		var cw := cos(w)
		var al := sin(w) / (2.0 * q)
		var a0 := 1.0 + al
		match type:
			"lp":
				b0 = (1.0 - cw) / 2.0; b1 = 1.0 - cw; b2 = b0
			"hp":
				b0 = (1.0 + cw) / 2.0; b1 = -(1.0 + cw); b2 = b0
			_:
				b0 = al; b1 = 0.0; b2 = -al
		a1 = -2.0 * cw
		a2 = 1.0 - al
		b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
	func run(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		return y

static func buf(sec: float, sr := SR) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * sr))
	return b

static func env(i: int, n: int, a: float, sr: float, dk: float) -> float:
	var t := i / sr
	if t < a: return t / a
	return exp(-(t - a) * dk)

## filtered noise burst with optional frequency sweep, added into b
static func noise(b: PackedFloat32Array, start: float, dur: float, type: String, f0: float, f1: float, q: float, peak: float, sr := SR, attack := 0.002) -> void:
	var bq := BQ.new(type, f0, q, sr)
	var s0 := int(start * sr)
	var n := mini(int(dur * sr * 1.6), b.size() - s0)
	var dk := 5.0 / dur
	for i in n:
		if i % 32 == 0 and f1 != f0: bq.set_f(f0 * pow(f1 / f0, minf(1.0, float(i) / (dur * sr))), q)
		b[s0 + i] += bq.run(randf() * 2.0 - 1.0) * peak * env(i, n, attack, sr, dk)

## swept oscillator (sine / tri / saw) into b
static func tone(b: PackedFloat32Array, start: float, dur: float, wave: String, f0: float, f1: float, peak: float, sr := SR, attack := 0.002) -> void:
	var s0 := int(start * sr)
	var n := mini(int(dur * sr * 1.6), b.size() - s0)
	var ph := 0.0
	var dk := 5.0 / dur
	for i in n:
		var f := f0 * pow(f1 / f0, minf(1.0, float(i) / (dur * sr)))
		ph += f / sr
		var x: float
		match wave:
			"sine": x = sin(ph * TAU)
			"tri": x = 1.0 - 4.0 * absf(fposmod(ph, 1.0) - 0.5)
			_: x = fposmod(ph, 1.0) * 2.0 - 1.0
		b[s0 + i] += x * peak * env(i, n, attack, sr, dk)

static func to_wav(b: PackedFloat32Array, sr := SR, loop := false) -> AudioStreamWAV:
	var peak := 0.0001
	for v in b: peak = maxf(peak, absf(v))
	var g := 0.92 / peak
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = b.size()
	return w

func _add(name: String, b: PackedFloat32Array, sr := SR, loop := false) -> void:
	var w := to_wav(b, sr, loop)
	call_deferred("_store", name, w)

func _store(name: String, w: AudioStreamWAV) -> void:
	if name.contains(":"):
		if not voices.has(name): voices[name] = []
		voices[name].append(w)
	else:
		if not streams.has(name): streams[name] = []
		streams[name].append(w)

func _generate_all() -> void:
	for v in 2:
		var b := buf(0.35)
		tone(b, 0, 0.18, "sine", 160.0, 42.0, 0.9)
		noise(b, 0, 0.05, "bp", 1700.0, 1700.0, 1.0, 0.5)
		noise(b, 0, 0.16, "lp", 1100.0, 300.0, 1.0, 0.6)
		noise(b, 0.01, 0.09, "bp", 600.0, 600.0, 3.0, 0.35)
		_add("hit", b)
		b = buf(0.7)
		tone(b, 0, 0.22, "sine", 180.0, 40.0, 1.0)
		tone(b, 0, 0.5, "sine", 70.0, 30.0, 0.8)
		noise(b, 0, 0.2, "lp", 1200.0, 250.0, 1.0, 0.7)
		for k in 5: noise(b, randf() * 0.06, 0.02, "hp", 2500.0 + randf() * 2500.0, 3000.0, 0.8, 0.5)
		_add("heavy", b)
		b = buf(0.25)
		for k in 6: noise(b, randf() * 0.07, 0.015 + randf() * 0.02, "hp", 2500.0 + randf() * 2500.0, 4000.0, 0.8, 0.6)
		noise(b, 0, 0.08, "lp", 500.0, 300.0, 1.0, 0.5)
		_add("crack", b)
		b = buf(0.6)
		for f in [480.0, 1270.0, 2210.0, 3420.0]: tone(b, 0, 0.35, "tri", f * randf_range(0.95, 1.05), f * 0.98, 0.16, SR, 0.001)
		noise(b, 0, 0.06, "lp", 700.0, 700.0, 1.0, 0.55)
		noise(b, 0, 0.03, "hp", 4000.0, 4000.0, 1.0, 0.3)
		_add("block", b)
		b = buf(0.35)
		noise(b, 0, 0.25, "bp", 380.0, 2400.0, 2.2, 0.5, SR, 0.1)
		_add("whoosh", b)
		b = buf(0.45)
		noise(b, 0, 0.25, "lp", 900.0, 180.0, 2.0, 0.6, SR, 0.003)
		for k in 4: noise(b, randf() * 0.12, 0.02, "bp", 1800.0 + randf() * 1500.0, 2000.0, 6.0, 0.3)
		_add("splat", b)
		b = buf(0.5)
		noise(b, 0, 0.14, "bp", 2500.0, 8000.0, 3.0, 0.5, SR, 0.005)
		tone(b, 0, 0.25, "sine", 3600.0, 2900.0, 0.1)
		noise(b, 0.04, 0.2, "lp", 900.0, 200.0, 2.0, 0.35)
		_add("slice", b)
		b = buf(1.1)
		noise(b, 0, 0.7, "lp", 400.0, 1200.0, 1.0, 0.55, SR, 0.05)
		noise(b, 0, 0.5, "bp", 900.0, 900.0, 1.0, 0.2, SR, 0.02)
		for k in 7: noise(b, randf() * 0.7, 0.01, "hp", 3000.0, 3000.0, 1.0, 0.3)
		_add("fire", b)
		b = buf(2.0)
		noise(b, 0, 1.4, "lp", 300.0, 60.0, 0.7, 0.9)
		tone(b, 0, 1.1, "sine", 60.0, 28.0, 0.9)
		noise(b, 0, 0.25, "bp", 1200.0, 1200.0, 1.0, 0.4)
		_add("boom", b)
	var b2 := buf(1.0)
	tone(b2, 0, 0.15, "sine", 55.0, 40.0, 0.7, SR, 0.005)
	tone(b2, 0.22, 0.18, "sine", 50.0, 38.0, 0.5, SR, 0.005)
	_add("heartbeat", b2)
	b2 = buf(3.5, VSR)
	noise(b2, 0.1, 0.3, "hp", 1500.0, 1500.0, 0.5, 0.15, VSR)
	noise(b2, 0.15, 3.0, "lp", 180.0, 60.0, 0.5, 0.4, VSR, 0.08)
	_add("thunder", b2, VSR)
	b2 = buf(4.0, VSR)
	for pr in [[1.0, 0.25], [2.0, 0.12], [2.76, 0.1], [5.4, 0.05], [0.5, 0.2]]:
		tone(b2, 0, 3.5, "sine", 98.0 * pr[0], 98.0 * pr[0] * 0.995, pr[1], VSR, 0.005)
	_add("bell", b2, VSR)
	b2 = buf(1.0, VSR)
	var ph := [0.0, 0.0, 0.0]
	var bq := BQ.new("bp", 1200.0, 2.0, VSR)
	for i in b2.size():
		var t := float(i) / VSR
		var s := 0.0
		for k in 3:
			var f := (500.0 + k * 170.0) * (1.0 + 1.6 * sin(minf(1.0, t / 0.7) * PI)) + sin(t * TAU * (9.0 + k)) * 30.0
			ph[k] += f / VSR
			s += fposmod(ph[k], 1.0) * 2.0 - 1.0
		b2[i] = bq.run(s) * env(i, b2.size(), 0.05, VSR, 4.0)
	_add("spectral", b2, VSR)
	b2 = buf(1.6, VSR)
	var bq2 := BQ.new("bp", 520.0, 1.5, VSR)
	var ph2 := [0.0, 0.0, 0.0]
	for i in b2.size():
		var t := float(i) / VSR
		var s := 0.0
		for k in 3:
			var f: float = [118.0, 131.0, 147.0][k] + sin(t * TAU * (23.0 + k * 4.0)) * 9.0
			ph2[k] += f / VSR
			s += fposmod(ph2[k], 1.0) * 2.0 - 1.0
		b2[i] = bq2.run(s) * minf(1.0, t / 0.15) * maxf(0.0, 1.0 - t / 1.6)
	_add("swarm", b2, VSR)
	# voices
	for id in VOICE_PROF:
		for kind in ["atk", "hurt", "scream", "die", "laugh", "roar"]:
			var n := 2 if kind in ["atk", "hurt"] else 1
			for k in n:
				_add(id + ":" + kind, _voice(VOICE_PROF[id], kind), VSR)
	_music()
	call_deferred("_done")

func _done() -> void:
	is_ready = true
	if G and G.has_method("on_audio_ready"): G.on_audio_ready()

func _voice(v: Dictionary, kind: String) -> PackedFloat32Array:
	var K: Array = {atk = [0.18, 1.15, 0.8, "a"], hurt = [0.3, 1.05, 0.7, "u"], scream = [1.1, 1.1, 1.35, "a"], die = [1.4, 1.15, 0.55, "o"], roar = [1.2, 1.0, 0.9, "a"], laugh = [1.1, 1.0, 1.0, "a"]}[kind]
	var Fm: Array = {a = [800.0, 1200.0, 2700.0], o = [520.0, 900.0, 2500.0], u = [400.0, 800.0, 2400.0]}[K[3]]
	var dur: float = K[0]
	var f0: float = v.f0 * randf_range(0.92, 1.08)
	var b := buf(dur + 0.1, VSR)
	var fs: float = v.fs
	var f1 := BQ.new("bp", Fm[0] * fs, 6.0, VSR)
	var f2 := BQ.new("bp", Fm[1] * fs, 9.0, VSR)
	var f3 := BQ.new("bp", Fm[2] * fs, 12.0, VSR)
	var nb := BQ.new("bp", 2200.0 * fs, 1.0, VSR)
	var ph := 0.0
	var dist: float = v.dist
	var rasp: float = v.rasp
	var vib_a := 0.05 if kind in ["scream", "die"] else 0.02
	var n := b.size()
	for i in n:
		var t := float(i) / VSR
		var u := t / dur
		var pc: float
		if u < 0.35: pc = lerpf(K[1], K[2] * (1.25 if kind == "scream" else 1.0), u / 0.35)
		else: pc = lerpf(K[2] * (1.25 if kind == "scream" else 1.0), K[2] * 0.85, (u - 0.35) / 0.65)
		var f := f0 * pc * (1.0 + sin(t * TAU * 6.0) * vib_a)
		ph += f / VSR
		var src := fposmod(ph, 1.0) * 2.0 - 1.0
		var s := f1.run(src) + f2.run(src) * 0.6 + f3.run(src) * 0.3
		if dist > 0.0: s = tanh(s * dist) * 0.6
		s += nb.run(randf() * 2.0 - 1.0) * rasp * 0.5
		var e: float
		if kind == "laugh":
			var pu := fposmod(t, 0.17) / 0.17
			e = (1.0 - pu) * minf(1.0, pu * 12.0) * maxf(0.0, 1.0 - u)
		else:
			e = minf(1.0, t / minf(0.05, dur * 0.2)) * maxf(0.0, 1.0 - u)
		b[i] = s * e
	return b

func _music() -> void:
	# fight: 4 bars @ 88 bpm, minor chords, war drums layer
	var bpm := 88.0
	var step := 60.0 / bpm / 4.0
	var bars := 4
	var length := step * 16 * bars
	var base := buf(length, VSR)
	var drums := buf(length, VSR)
	var chords := [[110.0, 130.8, 164.8], [87.3, 110.0, 130.8], [98.0, 116.5, 146.8], [82.4, 103.8, 123.5]]
	var lp := BQ.new("lp", 260.0, 3.0, VSR)
	var phs := [0.0, 0.0, 0.0]
	var pad := BQ.new("bp", 750.0, 2.0, VSR)
	var pph := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var n := base.size()
	for i in n:
		var t := float(i) / VSR
		var dr := 0.0
		for k in 3:
			var f: float = [55.0, 55.4, 82.4][k]
			phs[k] += f / VSR
			dr += fposmod(phs[k], 1.0) * 2.0 - 1.0
		if i % 64 == 0: lp.set_f(260.0 + 140.0 * sin(t * TAU * 0.07), 3.0)
		var bar := int(t / (step * 16))
		var ch: Array = chords[bar % 4]
		var ps := 0.0
		for k in 6:
			var f: float = ch[k % 3] * 2.0 * (1.003 if k >= 3 else 0.997)
			pph[k] += f / VSR
			ps += fposmod(pph[k], 1.0) * 2.0 - 1.0
		var bt := fposmod(t, step * 16) / (step * 16)
		base[i] = lp.run(dr) * 0.5 + pad.run(ps) * 0.12 * (0.6 + 0.4 * sin(bt * PI))
	var pat := [1.0, 0, 0, 0.6, 0, 0, 0.8, 0, 1.0, 0, 0.4, 0, 0.9, 0.3, 0.6, 0.5]
	for s in 16 * bars:
		var acc: float = pat[s % 16]
		if acc > 0.0:
			tone(drums, s * step, 0.45, "sine", 95.0, 38.0, 0.9 * acc, VSR)
			noise(drums, s * step, 0.12, "lp", 500.0, 120.0, 1.0, 0.4 * acc, VSR)
		if s % 32 == 24:
			for f in [310.0, 787.0, 1430.0]: tone(drums, s * step, 1.2, "tri", f, f * 0.99, 0.05, VSR)
	_add("music_fight", base, VSR, true)
	_add("drums_fight", drums, VSR, true)
	# menu: slow drone + choir pad + bell toll
	var mlen := 12.0
	var mb := buf(mlen, VSR)
	var lp2 := BQ.new("lp", 220.0, 2.0, VSR)
	var pad2 := BQ.new("bp", 700.0, 2.5, VSR)
	var mph := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for i in mb.size():
		var t := float(i) / VSR
		var dr := 0.0
		for k in 3:
			var f: float = [55.0, 55.3, 27.5][k]
			mph[k] += f / VSR
			dr += (fposmod(mph[k], 1.0) * 2.0 - 1.0) if k < 2 else sin(mph[k] * TAU) * 2.0
		var ch: Array = chords[0] if t < mlen * 0.5 else chords[1]
		var ps := 0.0
		for k in 6:
			var f: float = ch[k % 3] * 2.0 * (1.003 if k >= 3 else 0.997)
			mph[3 + k % 6] += f / VSR
			ps += fposmod(mph[3 + k % 6], 1.0) * 2.0 - 1.0
		var sw := sin(fposmod(t, mlen * 0.5) / (mlen * 0.5) * PI)
		mb[i] = lp2.run(dr) * 0.5 + pad2.run(ps) * 0.1 * sw
	for pr in [[1.0, 0.25], [2.0, 0.12], [2.76, 0.1], [0.5, 0.2]]:
		tone(mb, 0.0, 5.0, "sine", 98.0 * pr[0], 98.0 * pr[0] * 0.995, pr[1] * 0.6, VSR, 0.005)
	_add("music_menu", mb, VSR, true)
