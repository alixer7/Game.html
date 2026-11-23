shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

// Triplanar textured props: rocks, bark, masonry, wood. Moss on upward faces.
// COLOR.rgb tints (and carries baked AO), COLOR.a scales the moss amount.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_scale = 0.25;
uniform float moss_amount = 0.6;
uniform float moss_height = 0.62;
uniform float roughness = 0.9;
uniform bool use_uv = false;
uniform vec2 uv_scale = vec2(1.0, 1.0);

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wn);
	vec3 c;
	if (use_uv) {
		c = texture(albedo_tex, UV * uv_scale).rgb;
		NORMAL_MAP = texture(normal_tex, UV * uv_scale).rgb;
	} else {
		c = triplanar_tex(albedo_tex, v_wp, n, tex_scale);
		vec3 wn = triplanar_normal(normal_tex, v_wp, n, tex_scale);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
	c *= COLOR.rgb;
	float nz = texture(g_noise_tex, v_wp.xz * 0.11 + v_wp.y * 0.05).a;
	float m = smoothstep(moss_height, 1.0, n.y + (nz - 0.5) * 0.5) * moss_amount * COLOR.a;
	vec3 moss = texture(moss_tex, v_wp.xz * 0.2).rgb;
	c = mix(c, moss, clamp(m, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
}
