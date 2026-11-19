class_name CarAudio
extends Node3D
## Engine (two crossfaded synthesised loops pitched by rpm), tyres, wind,
## nitro, scraping, siren and impact one-shots.

var car: Car
var eng_on: Node
var eng_off: Node
var squeal: Node
var gravel: Node
var wind: Node
var nitro_p: Node
var scrape_p: Node
var siren: Node
var oneshot: Node
var scrape_level := 0.0
var player_mode := false
var _active := true


func _mk(key: String, vol := 0.0, three_d := true) -> Node:
	var p: Node
	if three_d:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 9.0
		p3.max_distance = 260.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.stream = Game.sfx.get_sound(key)
	p.volume_db = vol
	add_child(p)
	return p


func setup(c: Car) -> void:
	car = c
	player_mode = c.is_player
	var cyl: int = c.spec.get("cyl", 6)
	var cyl_key := 8
	if cyl <= 4:
		cyl_key = 4
	elif cyl <= 6:
		cyl_key = 6
	elif cyl >= 12:
		cyl_key = 12
	var td := not player_mode
	eng_on = _mk("engine:%d:on" % cyl_key, -6.0, td)
	eng_off = _mk("engine:%d:off" % cyl_key, -10.0, td)
	squeal = _mk("squeal", -80.0, td)
	gravel = _mk("gravel", -80.0, td)
	if player_mode:
		wind = _mk("wind", -80.0, false)
		nitro_p = _mk("nitro", -80.0, false)
	scrape_p = _mk("scrape", -80.0, td)
	if c.is_police:
		siren = _mk("siren", -80.0, true)
		(siren as AudioStreamPlayer3D).unit_size = 30.0
		(siren as AudioStreamPlayer3D).max_distance = 600.0
	oneshot = _mk("crash:0", 0.0, td)
	for p in [eng_on, eng_off, squeal, gravel, wind, nitro_p, scrape_p]:
		if p:
			p.play()


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	for p in [eng_on, eng_off, squeal, gravel, wind, nitro_p, scrape_p]:
		if p:
			if on:
				p.play()
			else:
				p.stop()


func _process(_delta: float) -> void:
	if car == null or not _active:
		return
	var rpm := car.rpm
	var load := car.engine_load
	var pitch := clampf(rpm / 2000.0, 0.3, 4.5)
	eng_on.pitch_scale = pitch
	eng_off.pitch_scale = pitch
	var base := -4.0 if player_mode else 0.0
	eng_on.volume_db = base + linear_to_db(clampf(0.15 + load * 0.85, 0.01, 1.0))
	eng_off.volume_db = base - 3.0 + linear_to_db(clampf(1.0 - load * 0.9, 0.01, 1.0))
	var sk := car.skid_amount
	var paved := car.surface in ["asphalt", "concrete", "cobble", "stone"]
	squeal.volume_db = linear_to_db(maxf(sk * (1.0 if paved else 0.2), 0.0001)) + (-3.0 if player_mode else 2.0)
	squeal.pitch_scale = 0.9 + sk * 0.2
	var loose := 0.0 if paved or car.grounded == 0 else clampf(car.speed_abs / 25.0, 0.0, 1.0)
	gravel.volume_db = linear_to_db(maxf(loose * 0.8 + sk * 0.3 * (0.0 if paved else 1.0), 0.0001)) - 2.0
	if wind:
		wind.volume_db = linear_to_db(maxf(clampf((car.speed_abs - 8.0) / 70.0, 0.0, 1.0), 0.0001)) - 4.0
		wind.pitch_scale = 0.8 + clampf(car.speed_abs / 90.0, 0.0, 0.6)
	if nitro_p:
		nitro_p.volume_db = -2.0 if car.nitro_active else -80.0
	scrape_p.volume_db = linear_to_db(maxf(scrape_level, 0.0001)) - 2.0
	if siren:
		var on: bool = car.controller != null and car.controller.get("siren_on") == true
		if on and not siren.playing:
			siren.play()
		elif not on and siren.playing:
			siren.stop()
		siren.volume_db = 2.0


func crash(severity: float) -> void:
	oneshot.stream = Game.sfx.get_sound("crash:%d" % (randi() % 3))
	oneshot.volume_db = linear_to_db(clampf(0.3 + severity * 0.7, 0.05, 1.0)) + 2.0
	oneshot.pitch_scale = randf_range(0.85, 1.15)
	oneshot.play()
	if player_mode:
		Game.vibrate(int(40 + severity * 80))


func shift_pop() -> void:
	if not player_mode:
		return
	oneshot.stream = Game.sfx.get_sound("pop")
	oneshot.volume_db = -8.0
	oneshot.pitch_scale = randf_range(0.9, 1.2)
	oneshot.play()


func thud(strength: float) -> void:
	oneshot.stream = Game.sfx.get_sound("thud")
	oneshot.volume_db = linear_to_db(clampf(strength * 0.6, 0.05, 1.0))
	oneshot.play()
