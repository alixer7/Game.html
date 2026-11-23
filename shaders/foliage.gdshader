shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

// Opaque canopy blobs, bushes, grass blades, flowers.
// COLOR.rgb = albedo (vertex painted, includes baked occlusion), COLOR.a = sway weight
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 backlight_color : source_color = vec3(0.32, 0.45, 0.08);
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.3;
uniform float leafy_noise = 0.35;
uniform float fade_far = 0.0;   // > 0: shrink instances into the ground near this distance
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 v_wp;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (fade_far > 0.0) {
		float d = length(origin - CAMERA_POSITION_WORLD);
		VERTEX *= 1.0 - smoothstep(fade_far * 0.72, fade_far, d);
	}
	float ph = dot(origin, vec3(0.13, 0.0, 0.17));
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * wind_speed + ph + wp.y * 0.25) * 0.65 + sin(TIME * wind_speed * 2.37 + ph * 1.7 + wp.x * 0.3) * 0.35;
	float sway = COLOR.a;
	VERTEX.x += w * wind_strength * sway;
	VERTEX.z += w * wind_strength * sway * 0.55;
	v_wp = wp;
}

void fragment() {
	float n = texture(noise_tex, v_wp.xz * 0.35 + v_wp.y * 0.21).a;
	vec3 c = COLOR.rgb * tint * (1.0 - leafy_noise * 0.5 + leafy_noise * n);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = backlight_color;
}
