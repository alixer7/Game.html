class_name SkyWeather
extends Node3D
## دورة الليل والنهار، الشمس والقمر، السماء، الضباب، والطقس (مطر، عواصف، ثلج، ضباب).

signal weather_changed(name: String)

const WEATHER_NAMES := {"clear": "صحو", "cloudy": "غائم", "rain": "ممطر", "storm": "عاصفة رعدية", "fog": "ضباب", "snow": "تساقط ثلوج"}

var world: Node
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var we: WorldEnvironment
var hours := 8.0
var weather := "clear"
var weather_timer := 3.0
var cloud := 0.2
var rain := 0.0
var mist := 0.0
var wind := 1.0
var storm := 0.0
var wetness := 0.0
var snow_cover := 0.0
var snowing := false
var _t_cloud := 0.2
var _t_rain := 0.0
var _t_mist := 0.0
var _t_wind := 1.0
var _t_storm := 0.0
var rain_fx: GPUParticles3D
var snow_fx: GPUParticles3D
var _lightning := 8.0
var _flash := 0.0
var _thunder_delay := -1.0
var quality := 1

const KEYS := [
	[0.0, Color(0.012, 0.018, 0.045), Color(0.04, 0.05, 0.09), Color(0.06, 0.07, 0.12)],
	[4.8, Color(0.03, 0.045, 0.1), Color(0.12, 0.1, 0.16), Color(0.08, 0.08, 0.13)],
	[6.0, Color(0.2, 0.3, 0.55), Color(0.95, 0.56, 0.32), Color(0.28, 0.25, 0.27)],
	[7.5, Color(0.27, 0.46, 0.8), Color(0.75, 0.78, 0.84), Color(0.38, 0.4, 0.45)],
	[12.0, Color(0.2, 0.42, 0.82), Color(0.66, 0.78, 0.9), Color(0.44, 0.47, 0.52)],
	[16.5, Color(0.24, 0.42, 0.76), Color(0.78, 0.76, 0.72), Color(0.42, 0.42, 0.45)],
	[18.4, Color(0.18, 0.22, 0.45), Color(0.98, 0.46, 0.24), Color(0.3, 0.24, 0.24)],
	[19.8, Color(0.04, 0.05, 0.13), Color(0.2, 0.13, 0.19), Color(0.1, 0.09, 0.13)],
	[24.0, Color(0.012, 0.018, 0.045), Color(0.04, 0.05, 0.09), Color(0.06, 0.07, 0.12)],
]

func setup(w: Node, q: int) -> void:
	world = w
	quality = q
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_tex", MeshFactory.cloud_tex)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32 if q == 0 else Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_density = 0.002
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.35
	env.fog_sun_scatter = 0.15
	env.glow_enabled = q >= 1
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 55.0 if q < 2 else 90.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	add_child(sun)
	rain_fx = _make_precip(false)
	snow_fx = _make_precip(true)

func _make_precip(is_snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = [350, 800, 1400][quality] if not is_snow else [300, 600, 1000][quality]
	p.lifetime = 1.1 if not is_snow else 4.5
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 1, 18)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 3.0 if not is_snow else 25.0
	pm.initial_velocity_min = 16.0 if not is_snow else 0.8
	pm.initial_velocity_max = 20.0 if not is_snow else 1.6
	pm.gravity = Vector3(0, -9.8, 0) if not is_snow else Vector3(0.3, -1.2, 0.2)
	if is_snow:
		pm.turbulence_enabled = false
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.7) if not is_snow else Vector2(0.07, 0.07)
	q.material = MeshFactory.mat("rain" if not is_snow else "snowflake")
	p.draw_pass_1 = q
	add_child(p)
	return p

func total_hours() -> float:
	return hours

func day() -> int:
	return int(hours / 24.0) + 1

func hour_of_day() -> float:
	return fmod(hours, 24.0)

func is_night() -> bool:
	var h := hour_of_day()
	return h < 5.5 or h > 20.0

func clock_text() -> String:
	var h := hour_of_day()
	return "اليوم %d  %02d:%02d" % [day(), int(h), int(fmod(h, 1.0) * 60.0)]

func darkness() -> float:
	var h := hour_of_day()
	var sun_y := sin((h - 6.0) / 12.0 * PI)
	return clampf(1.0 - (sun_y + 0.1) * 3.0, 0.0, 1.0)

func advance(game_hours: float) -> void:
	hours += game_hours

func _key_colors(h: float) -> Array:
	for i in range(KEYS.size() - 1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t = (h - a[0]) / (b[0] - a[0])
			return [a[1].lerp(b[1], t), a[2].lerp(b[2], t), a[3].lerp(b[3], t)]
	return [KEYS[0][1], KEYS[0][2], KEYS[0][3]]

func tick(dt: float, ppos: Vector3, local_temp: float, biome: int) -> void:
	var day_minutes: float = Game.settings.get("day_minutes", 24.0)
	var hrs_per_sec := 24.0 / (day_minutes * 60.0)
	hours += dt * hrs_per_sec * world.time_scale
	var h := hour_of_day()
	_weather_logic(dt * hrs_per_sec * world.time_scale, biome)
	var k := dt * 0.15
	cloud = lerpf(cloud, _t_cloud, k)
	rain = lerpf(rain, _t_rain, k)
	mist = lerpf(mist, _t_mist, k)
	wind = lerpf(wind, _t_wind, k)
	storm = lerpf(storm, _t_storm, k)
	snowing = rain > 0.15 and local_temp < 1.0
	if rain > 0.2 and not snowing:
		wetness = minf(1.0, wetness + dt / 60.0)
	else:
		wetness = maxf(0.0, wetness - dt / 240.0)
	if snowing:
		snow_cover = minf(1.0, snow_cover + dt / 120.0 * rain)
	elif local_temp > 2.0:
		snow_cover = maxf(0.0, snow_cover - dt / 300.0 * clampf(local_temp / 10.0, 0.2, 2.0))
	MeshFactory.set_weather_params(wetness, snow_cover, wind)
	world.terrain.water.material_override.set_shader_parameter("storm", storm)
	# الشمس والقمر
	var a := (h - 6.0) / 12.0 * PI
	var sun_dir := Vector3(cos(a), sin(a), 0.35).normalized()
	var moon_dir := -sun_dir
	var sun_k := smoothstep(-0.06, 0.15, sun_dir.y)
	var moon_k := smoothstep(-0.06, 0.15, moon_dir.y)
	var cols := _key_colors(h)
	var top: Color = cols[0]
	var hor: Color = cols[1]
	var amb: Color = cols[2]
	var overcast := clampf(cloud * 0.8 + rain * 0.4, 0.0, 1.0)
	var grey := Color(0.5, 0.52, 0.55) * (0.15 + 0.85 * sun_k)
	top = top.lerp(grey * 0.9, overcast * 0.75)
	hor = hor.lerp(grey, overcast * 0.6)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(0.5))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("night", 1.0 - sun_k)
	sky_mat.set_shader_parameter("cloud_cover", clampf(cloud, 0.0, 1.0))
	var cc := Color(1, 1, 1).lerp(Color(0.45, 0.47, 0.5), overcast) * (0.12 + 0.88 * sun_k)
	sky_mat.set_shader_parameter("cloud_color", cc)
	var low_sun := 1.0 - smoothstep(0.05, 0.45, sun_dir.y)
	var sun_col := Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.5, 0.25), low_sun)
	sky_mat.set_shader_parameter("sun_color", sun_col)
	var flash := 0.0
	if _flash > 0.0:
		_flash -= dt
		flash = maxf(_flash, 0.0) * 8.0
	if sun_k >= moon_k * 0.3:
		sun.global_transform.basis = Basis.looking_at(-sun_dir, Vector3.UP)
		sun.light_color = sun_col
		sun.light_energy = 1.35 * sun_k * (1.0 - overcast * 0.6) + flash
	else:
		sun.global_transform.basis = Basis.looking_at(-moon_dir, Vector3.UP)
		sun.light_color = Color(0.55, 0.62, 0.85)
		sun.light_energy = 0.16 * moon_k * (1.0 - overcast * 0.7) + flash
	sun.global_position = ppos
	env.ambient_light_color = amb.lerp(grey * 0.8, overcast * 0.4) + Color(flash, flash, flash) * 0.3
	env.ambient_light_energy = 1.0
	env.fog_light_color = hor.lerp(grey, overcast * 0.5)
	env.fog_density = 0.0016 + overcast * 0.0012 + rain * 0.003 + mist + (0.004 if snowing else 0.0)
	# الهطول
	var show_precip := rain > 0.12
	rain_fx.emitting = show_precip and not snowing
	snow_fx.emitting = show_precip and snowing
	rain_fx.global_position = ppos + Vector3(0, 14, 0)
	snow_fx.global_position = ppos + Vector3(0, 10, 0)
	rain_fx.amount_ratio = clampf(rain, 0.0, 1.0)
	snow_fx.amount_ratio = clampf(rain, 0.0, 1.0)
	# البرق
	if storm > 0.5:
		_lightning -= dt
		if _lightning <= 0.0:
			_lightning = randf_range(6.0, 18.0)
			_flash = 0.12
			_thunder_delay = randf_range(0.4, 2.5)
	if _thunder_delay > 0.0:
		_thunder_delay -= dt
		if _thunder_delay <= 0.0:
			Sfx.play("thunder", null, -2.0, 0.2)

func _weather_logic(dh: float, biome: int) -> void:
	weather_timer -= dh
	if weather_timer > 0.0:
		return
	weather_timer = randf_range(1.5, 5.0)
	var probs := {"clear": 4.0, "cloudy": 2.5, "rain": 1.6, "storm": 0.5, "fog": 0.7}
	match biome:
		WorldGen.DESERT, WorldGen.VOLCANIC:
			probs = {"clear": 8.0, "cloudy": 1.5, "rain": 0.2, "storm": 0.1, "fog": 0.1}
		WorldGen.SWAMP:
			probs = {"clear": 2.0, "cloudy": 2.5, "rain": 2.5, "storm": 0.8, "fog": 2.0}
		WorldGen.TAIGA, WorldGen.TUNDRA, WorldGen.SNOW:
			probs = {"clear": 2.5, "cloudy": 3.0, "rain": 2.5, "storm": 0.4, "fog": 1.2}
		WorldGen.FOREST:
			probs = {"clear": 3.0, "cloudy": 2.5, "rain": 2.0, "storm": 0.6, "fog": 1.0}
	var total := 0.0
	for k in probs:
		total += probs[k]
	var x := randf() * total
	var pick := "clear"
	for k in probs:
		x -= probs[k]
		if x <= 0.0:
			pick = k
			break
	set_weather(pick)

func set_weather(w: String) -> void:
	weather = w
	match w:
		"clear":
			_t_cloud = randf_range(0.05, 0.3); _t_rain = 0.0; _t_mist = 0.0; _t_wind = 0.8; _t_storm = 0.0
		"cloudy":
			_t_cloud = randf_range(0.55, 0.75); _t_rain = 0.0; _t_mist = 0.0; _t_wind = 1.3; _t_storm = 0.0
		"rain":
			_t_cloud = 0.85; _t_rain = randf_range(0.45, 0.75); _t_mist = 0.002; _t_wind = 1.6; _t_storm = 0.0
		"storm":
			_t_cloud = 0.98; _t_rain = 1.0; _t_mist = 0.003; _t_wind = 2.8; _t_storm = 1.0
		"fog":
			_t_cloud = 0.5; _t_rain = 0.0; _t_mist = 0.02; _t_wind = 0.4; _t_storm = 0.0
	weather_changed.emit(w)

func weather_name() -> String:
	if snowing:
		return WEATHER_NAMES["snow"]
	return WEATHER_NAMES.get(weather, weather)

func to_data() -> Dictionary:
	return {"hours": hours, "weather": weather, "timer": weather_timer, "wet": wetness, "snow": snow_cover}

func from_data(d: Dictionary) -> void:
	hours = float(d.get("hours", 8.0))
	set_weather(str(d.get("weather", "clear")))
	weather_timer = float(d.get("timer", 2.0))
	wetness = float(d.get("wet", 0.0))
	snow_cover = float(d.get("snow", 0.0))
	cloud = _t_cloud
	rain = _t_rain
	mist = _t_mist
	storm = _t_storm
