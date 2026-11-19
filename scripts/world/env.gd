class_name GameEnv
extends Node3D
## Sun, sky, fog and post-processing, configured by graphics quality and time of day.

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial

# elevation, azimuth (deg), sun colour, energy, zenith, horizon, fog colour, fog density, ambient
const PRESETS := [
	[24.0, 120.0, Color(1.0, 0.93, 0.82), 1.6, Color(0.20, 0.42, 0.78), Color(0.72, 0.82, 0.94), Color(0.70, 0.78, 0.88), 0.00016, 0.85],
	[16.0, 235.0, Color(1.0, 0.78, 0.55), 1.9, Color(0.18, 0.35, 0.68), Color(0.92, 0.80, 0.66), Color(0.85, 0.75, 0.62), 0.0002, 0.75],
	[62.0, 200.0, Color(1.0, 0.98, 0.94), 1.9, Color(0.14, 0.36, 0.76), Color(0.66, 0.78, 0.92), Color(0.70, 0.80, 0.92), 0.00012, 1.0],
	[5.0, 262.0, Color(1.0, 0.52, 0.28), 1.5, Color(0.16, 0.22, 0.44), Color(0.98, 0.58, 0.36), Color(0.78, 0.52, 0.42), 0.00028, 0.6],
]


func setup(quality: int, tod: int, view: float) -> void:
	var p: Array = PRESETS[clampi(tod, 0, PRESETS.size() - 1)]
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	sun.rotation_degrees = Vector3(-p[0], p[1], 0.0)
	sun.light_color = p[2]
	sun.light_energy = p[3]
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = quality >= 0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	match quality:
		0:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 70.0
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 140.0
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 320.0
			sun.directional_shadow_split_1 = 0.06
			sun.directional_shadow_split_2 = 0.18
			sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = quality >= 2

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("zenith_color", p[4])
	sky_mat.set_shader_parameter("horizon_color", p[5])
	sky_mat.set_shader_parameter("sun_tint", p[2])
	sky_mat.set_shader_parameter("clouds", 0.45 if tod != 2 else 0.35)
	sky_mat.set_shader_parameter("quality", mini(quality, 2))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128 if quality < 2 else Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if quality >= 2 else Sky.PROCESS_MODE_QUALITY

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = p[8]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = p[6]
	env.fog_density = p[7] * lerpf(1.3, 0.8, view)
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.fog_height = 60.0
	env.fog_height_density = 0.0002
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	if quality >= 2:
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
		env.ssao_power = 1.4
	if quality >= 3:
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssil_enabled = true
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.004
		env.volumetric_fog_length = 180.0
		env.volumetric_fog_anisotropy = 0.5
		env.volumetric_fog_albedo = p[6]
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# viewport level anti-aliasing / scaling
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(Game.settings.render_scale, 0.5, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_2X if quality >= 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality <= 2 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = quality >= 3
	vp.mesh_lod_threshold = 2.0 if quality < 2 else 1.0
