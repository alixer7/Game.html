extends Node

## Procedural CTR-Style Audio Synthesizer & Soundbank.
## Synthesizes punchy arcade SFX, dynamic engine/drift loops, and upbeat racing music at startup.

const MIX_RATE := 22050

var _sounds: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _engine_player: AudioStreamPlayer
var _drift_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer

var _engine_active: bool = false
var _music_playing: bool = false
var _fruit_combo: int = 0
var _fruit_combo_timer: float = 0.0

func _ready() -> void:
	# Skip audio hardware init in headless CLI tests safely, still build pool cleanly
	for i in range(12):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_engine_player = AudioStreamPlayer.new()
	add_child(_engine_player)
	_drift_player = AudioStreamPlayer.new()
	add_child(_drift_player)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)

	_build_soundbank()
	_engine_player.stream = _sounds["engine_loop"]
	_drift_player.stream = _sounds["drift_loop"]
	_music_player.stream = _sounds["music_race"]
	_update_volumes()
	if GameState:
		GameState.settings_changed.connect(_update_volumes)

func _process(delta: float) -> void:
	if _fruit_combo_timer > 0.0:
		_fruit_combo_timer -= delta
		if _fruit_combo_timer <= 0.0:
			_fruit_combo = 0

func _update_volumes() -> void:
	var m_vol := GameState.music_volume if GameState else 0.5
	_music_player.volume_db = linear_to_db(maxf(0.0001, m_vol * 0.42))
	if m_vol <= 0.01 and _music_player.playing:
		_music_player.stop()
	elif m_vol > 0.01 and _music_playing and not _music_player.playing:
		_music_player.play()

func start_music(is_menu: bool = false) -> void:
	var target: AudioStreamWAV = _sounds["music_menu"] if is_menu else _sounds["music_race"]
	if _music_player.stream != target:
		_music_player.stream = target
		_music_player.stop()
	_music_playing = true
	if (GameState.music_volume if GameState else 0.5) > 0.01:
		if not _music_player.playing:
			_music_player.play()
	_update_volumes()

func stop_music() -> void:
	_music_playing = false
	_music_player.stop()

func set_engine_active(active: bool) -> void:
	_engine_active = active
	if active:
		if not _engine_player.playing:
			_engine_player.volume_db = -24.0
			_engine_player.play()
		if not _drift_player.playing:
			_drift_player.volume_db = -60.0
			_drift_player.play()
	else:
		_engine_player.stop()
		_drift_player.stop()

func update_kart_audio(speed_ratio: float, fire_tier: int, is_drifting: bool, is_airborne: bool, rev_boost: float = 0.0) -> void:
	if not _engine_active:
		return
	var sfx_v := GameState.sfx_volume if GameState else 0.8
	if sfx_v <= 0.01:
		_engine_player.volume_db = -80.0
		_drift_player.volume_db = -80.0
		return
	var tier_pitch := 0.0
	match fire_tier:
		1: tier_pitch = 0.14
		2: tier_pitch = 0.28
		3: tier_pitch = 0.45
		4: tier_pitch = 0.68
	var target_pitch := clampf(0.72 + speed_ratio * 0.95 + tier_pitch + rev_boost * 0.45 + (0.08 if is_airborne else 0.0), 0.65, 2.45)
	_engine_player.pitch_scale = lerpf(_engine_player.pitch_scale, target_pitch, 0.16)
	var eng_lin := sfx_v * (0.18 + clampf(speed_ratio, 0.0, 1.2) * 0.16 + float(fire_tier) * 0.025)
	_engine_player.volume_db = linear_to_db(maxf(0.001, eng_lin))

	var drift_lin := sfx_v * (0.20 if (is_drifting and not is_airborne) else 0.0001)
	_drift_player.volume_db = lerpf(_drift_player.volume_db, linear_to_db(maxf(0.0001, drift_lin)), 0.25)
	_drift_player.pitch_scale = lerpf(_drift_player.pitch_scale, 0.92 + speed_ratio * 0.35, 0.15)

func play_sfx(name: String, pitch: float = 1.0, vol_mult: float = 1.0) -> void:
	if not _sounds.has(name):
		return
	var sfx_v := (GameState.sfx_volume if GameState else 0.8) * vol_mult
	if sfx_v <= 0.01:
		return
	var p := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	p.stream = _sounds[name]
	p.pitch_scale = clampf(pitch, 0.4, 2.6)
	p.volume_db = linear_to_db(clampf(sfx_v * 0.55, 0.001, 1.2))
	p.play()

func play_fruit() -> void:
	_fruit_combo = mini(_fruit_combo + 1, 8)
	_fruit_combo_timer = 1.4
	play_sfx("fruit", 0.92 + float(_fruit_combo) * 0.075, 0.9)

func play_drift_boost(stage: int, is_perfect: bool) -> void:
	var key := "boost_1" if stage <= 1 else ("boost_2" if stage == 2 else "boost_3")
	play_sfx(key, 1.08 if is_perfect else 0.94, 1.15 if is_perfect else 0.9)

# --- Procedural WAV Builders ---

func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.mix_rate = MIX_RATE
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s := clampi(int(clampf(samples[i], -1.0, 1.0) * 32767.0), -32768, 32767)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

func _build_soundbank() -> void:
	_sounds["hop"] = _synth_sweep(0.14, 190.0, 520.0, 0.7, "sine_punch")
	_sounds["land"] = _synth_sweep(0.11, 150.0, 48.0, 0.75, "thump")
	_sounds["bump"] = _synth_sweep(0.14, 240.0, 68.0, 0.88, "wood_smash")
	_sounds["boost_1"] = _synth_boost(0.32, 240.0, 520.0, 0.35)
	_sounds["boost_2"] = _synth_boost(0.36, 320.0, 680.0, 0.42)
	_sounds["boost_3"] = _synth_boost(0.44, 420.0, 920.0, 0.50)
	_sounds["sacred_fire"] = _synth_boost(0.55, 280.0, 1180.0, 0.65)
	_sounds["blue_fire"] = _synth_blue_fire(0.70)
	_sounds["backfire"] = _synth_sweep(0.24, 160.0, 55.0, 0.85, "noise_pop")
	_sounds["fruit"] = _synth_chime([587.33, 880.0], 0.16)
	_sounds["crate"] = _synth_sweep(0.22, 260.0, 75.0, 0.9, "wood_smash")
	_sounds["countdown_beep"] = _synth_tone(0.18, 523.25, 0.7)
	_sounds["countdown_go"] = _synth_chime([523.25, 659.25, 783.99, 1046.5], 0.42)
	_sounds["shortcut"] = _synth_chime([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.55)
	_sounds["tnt_tick"] = _synth_tone(0.06, 980.0, 0.75)
	_sounds["explosion"] = _synth_sweep(0.55, 190.0, 28.0, 1.0, "explosion")
	_sounds["shield"] = _synth_sweep(0.28, 360.0, 760.0, 0.55, "sine_punch")
	_sounds["missile"] = _synth_sweep(0.35, 820.0, 310.0, 0.7, "noise_pop")
	_sounds["mask"] = _synth_chime([392.0, 493.88, 587.33, 783.99, 987.77], 0.48)
	_sounds["lap_chime"] = _synth_chime([440.0, 554.37, 659.25, 880.0], 0.40)
	_sounds["victory"] = _synth_chime([523.25, 659.25, 783.99, 659.25, 1046.5], 0.78)
	_sounds["ui_click"] = _synth_tone(0.055, 720.0, 0.45)
	_sounds["ui_confirm"] = _synth_chime([520.0, 780.0], 0.14)
	_sounds["engine_loop"] = _synth_engine_loop()
	_sounds["drift_loop"] = _synth_drift_loop()
	_sounds["music_race"] = _synth_music_loop(false)
	_sounds["music_menu"] = _synth_music_loop(true)

func _synth_tone(dur: float, freq: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var env := pow(1.0 - float(i) / float(n), 1.4)
		var v := sin(TAU * freq * t) * 0.7 + sin(TAU * freq * 2.0 * t) * 0.25
		s[i] = v * env * amp
	return _make_wav(s)

func _synth_sweep(dur: float, f0: float, f1: float, amp: float, mode: String) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 17.0)
	for i in range(n):
		var u := float(i) / float(n)
		var freq := lerpf(f0, f1, u)
		phase += TAU * freq / MIX_RATE
		var env := (1.0 - u) * minf(1.0, u * 35.0)
		var v := 0.0
		match mode:
			"sine_punch":
				v = sin(phase) * 0.8 + sin(phase * 2.0) * 0.2
			"thump":
				v = sin(phase) * 0.85 + rng.randf_range(-0.2, 0.2) * (1.0 - u)
			"noise_pop":
				v = sin(phase) * 0.45 + rng.randf_range(-0.65, 0.65)
			"wood_smash":
				var crack := rng.randf_range(-1.0, 1.0) * (1.0 if u < 0.35 else 0.4)
				v = sin(phase) * 0.35 + crack * 0.75
			"explosion":
				v = sin(phase) * 0.55 + rng.randf_range(-0.9, 0.9) * pow(1.0 - u, 0.7)
		s[i] = clampf(v * env * amp, -1.0, 1.0)
	return _make_wav(s)

func _synth_boost(dur: float, f0: float, f1: float, noise_mix: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f1)
	var lp := 0.0
	for i in range(n):
		var u := float(i) / float(n)
		var freq := lerpf(f0, f1, pow(u, 0.65))
		phase += TAU * freq / MIX_RATE
		var raw_noise := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw_noise, 0.18 + u * 0.25)
		var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
		var env := minf(1.0, u * 25.0) * pow(1.0 - u, 1.15)
		s[i] = clampf((saw * 0.38 + sin(phase) * 0.32 + lp * noise_mix * 1.4) * env, -1.0, 1.0)
	return _make_wav(s)

func _synth_blue_fire(dur: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4042
	for i in range(n):
		var u := float(i) / float(n)
		var f1 := lerpf(320.0, 1680.0, pow(u, 0.55))
		var f2 := lerpf(640.0, 2400.0, pow(u, 0.7))
		p1 += TAU * f1 / MIX_RATE
		p2 += TAU * f2 / MIX_RATE
		var crackle := rng.randf_range(-0.7, 0.7) * (0.4 + 0.6 * absf(sin(u * 45.0)))
		var env := minf(1.0, u * 30.0) * pow(1.0 - u, 0.9)
		s[i] = clampf((sin(p1) * 0.42 + sin(p2) * 0.28 + crackle * 0.45) * env, -1.0, 1.0)
	return _make_wav(s)

func _synth_chime(notes: Array, total_dur: float) -> AudioStreamWAV:
	var n := int(total_dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var step := float(n) / float(notes.size())
	for i in range(n):
		var idx := mini(notes.size() - 1, int(float(i) / step))
		var local_u := fmod(float(i), step) / step
		var freq := float(notes[idx])
		var t := float(i) / MIX_RATE
		var env := minf(1.0, local_u * 25.0) * pow(1.0 - local_u, 0.85)
		var tail := pow(1.0 - float(i) / float(n), 0.5)
		var wave := sin(TAU * freq * t) * 0.65 + sin(TAU * freq * 2.0 * t) * 0.22 + sin(TAU * freq * 3.0 * t) * 0.1
		s[i] = clampf(wave * env * tail * 0.78, -1.0, 1.0)
	return _make_wav(s)

func _synth_engine_loop() -> AudioStreamWAV:
	# Seamless 0.25s period at 88Hz fundamental (exact integer cycles for zero click!)
	var base_freq := 88.0
	var cycles := 22
	var n := int(round(float(cycles) / base_freq * MIX_RATE))
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var ph := TAU * float(cycles) * float(i) / float(n)
		var v := sin(ph) * 0.45 + sin(ph * 2.0) * 0.28 + sin(ph * 3.0) * 0.15 + sin(ph * 4.0) * 0.08
		# Subtle cartoon kart purr modulation
		var purr := 0.82 + 0.18 * sin(ph * 0.5)
		s[i] = clampf(v * purr * 0.65, -1.0, 1.0)
	return _make_wav(s, true)

func _synth_drift_loop() -> AudioStreamWAV:
	var n := int(0.4 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var bp1 := 0.0
	var bp2 := 0.0
	for i in range(n):
		var noise := rng.randf_range(-1.0, 1.0)
		bp1 = lerpf(bp1, noise, 0.35)
		bp2 = lerpf(bp2, bp1, 0.12)
		var screech := (bp1 - bp2) * 1.8
		var squeal := sin(TAU * 1340.0 * float(i) / MIX_RATE) * 0.16
		# Fade ends for seamless loop
		var u := float(i) / float(n)
		var win := sin(u * PI)
		s[i] = clampf((screech + squeal) * (0.65 + 0.35 * win) * 0.65, -1.0, 1.0)
	return _make_wav(s, true)

func _synth_music_loop(chill_menu: bool) -> AudioStreamWAV:
	# Upbeat tropical-funky CTR-inspired chiptune-marimba & bass loop!
	var bpm := 124.0 if chill_menu else 148.0
	var step_sec := 60.0 / bpm / 2.0 # eighth notes
	var num_steps := 32 # 4 bars seamless loop
	var total_dur := step_sec * float(num_steps)
	var n := int(total_dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)

	# D Dorian / Mixolydian upbeat kart racing riff (Hz)
	var bass_seq := [
		146.83, 0.0, 146.83, 174.61, 196.0, 0.0, 174.61, 164.81,
		146.83, 0.0, 146.83, 220.0, 196.0, 0.0, 174.61, 146.83,
		130.81, 0.0, 130.81, 164.81, 196.0, 0.0, 164.81, 130.81,
		146.83, 164.81, 174.61, 196.0, 220.0, 0.0, 196.0, 164.81
	]
	var lead_seq := [
		587.33, 0.0, 659.25, 783.99, 0.0, 659.25, 587.33, 523.25,
		587.33, 0.0, 880.0, 783.99, 659.25, 0.0, 587.33, 0.0,
		523.25, 0.0, 659.25, 783.99, 880.0, 0.0, 783.99, 659.25,
		587.33, 659.25, 783.99, 880.0, 1046.5, 0.0, 880.0, 783.99
	]
	if chill_menu:
		lead_seq = [
			587.33, 0.0, 0.0, 659.25, 783.99, 0.0, 587.33, 0.0,
			523.25, 0.0, 659.25, 0.0, 587.33, 0.0, 0.0, 0.0,
			440.0, 0.0, 523.25, 0.0, 587.33, 0.0, 659.25, 0.0,
			783.99, 0.0, 659.25, 587.33, 523.25, 0.0, 440.0, 0.0
		]
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var samples_per_step := float(n) / float(num_steps)
	for i in range(n):
		var step_idx := mini(num_steps - 1, int(float(i) / samples_per_step))
		var local_u := fmod(float(i), samples_per_step) / samples_per_step
		var t := float(i) / MIX_RATE
		var mix := 0.0

		# Punchy bass
		var bf := float(bass_seq[step_idx])
		if bf > 1.0:
			var benv := minf(1.0, local_u * 20.0) * pow(1.0 - local_u, 0.9)
			var sq := 1.0 if sin(TAU * bf * t) >= 0.0 else -1.0
			mix += (sin(TAU * bf * t) * 0.6 + sq * 0.25) * benv * 0.34

		# Marimba / Brass lead
		var lf := float(lead_seq[step_idx])
		if lf > 1.0:
			var lenv := minf(1.0, local_u * 30.0) * pow(1.0 - local_u, 1.35)
			var marimba := sin(TAU * lf * t) * 0.65 + sin(TAU * lf * 2.0 * t) * 0.24 + sin(TAU * lf * 4.0 * t) * 0.1
			mix += marimba * lenv * 0.28

		# Kick drum on steps 0, 4, 8, 12...
		if (step_idx % 4) == 0 and local_u < 0.45:
			var ku := local_u / 0.45
			var kf := lerpf(135.0, 42.0, ku)
			mix += sin(TAU * kf * (local_u * step_sec)) * (1.0 - ku) * 0.36

		# Snare/shaker on off-beats 2, 6, 10...
		if (step_idx % 4) == 2 and local_u < 0.32:
			var su := local_u / 0.32
			mix += rng.randf_range(-1.0, 1.0) * (1.0 - su) * (0.14 if chill_menu else 0.24)
		elif (step_idx % 2) == 1 and local_u < 0.16 and not chill_menu:
			mix += rng.randf_range(-1.0, 1.0) * (1.0 - local_u / 0.16) * 0.10

		s[i] = clampf(mix, -0.95, 0.95)
	return _make_wav(s, true)
