shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

// UV.x = lateral metres, UV.y = metres along the road.
// COLOR.r = edge factor (0 centre -> 1 outer skirt), COLOR.g = tyre wear, COLOR.b = wetness,
// COLOR.a = curb stripe mask
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale = 0.22;
uniform vec3 tint : source_color = vec3(1.0);
uniform float edge_to_grass = 1.0;
uniform vec3 curb_a : source_color = vec3(0.92, 0.88, 0.8);
uniform vec3 curb_b : source_color = vec3(0.78, 0.22, 0.14);
uniform float roughness = 0.88;
uniform float normal_depth = 1.0;

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 c = texture(albedo_tex, uv).rgb * tint;
	float n = texture(g_noise_tex, v_wp.xz * 0.06).a;
	float macro = texture(g_noise_tex, v_wp.xz * 0.008).r;
	c *= 0.9 + macro * 0.2;
	// tyre-polished racing line
	c *= 1.0 - COLOR.g * 0.22;
	// curbs
	float stripe = step(0.5, fract(UV.y / 3.0));
	c = mix(c, mix(curb_a, curb_b, stripe) * (0.85 + 0.15 * n), COLOR.a);
	// irregular blend into the shared world grass at the shoulders
	float edge = smoothstep(0.45, 0.95, COLOR.r + (n - 0.5) * 0.55);
	c = mix(c, world_grass(v_wp), edge * edge_to_grass);
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - edge);
	ROUGHNESS = mix(roughness, 0.25, COLOR.b);
	SPECULAR = 0.35;
}
