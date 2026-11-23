shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/common.gdshaderinc"

// Vertex colour splat: r = dirt, g = rock, b = sand/wet, a = moss
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float rock_scale = 0.07;
uniform float detail_fade = 140.0;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wn);
	vec4 s = COLOR;
	float nz = texture(g_noise_tex, v_wp.xz * 0.05).a;
	vec3 col = world_grass(v_wp);
	vec3 dirt = texture(dirt_tex, v_wp.xz * 0.09).rgb;
	vec3 sand = texture(sand_tex, v_wp.xz * 0.13).rgb;
	vec3 moss = texture(moss_tex, v_wp.xz * 0.15).rgb;
	float rock_w = max(s.g, smoothstep(0.80, 0.62, n.y));
	float dirt_w = smoothstep(0.15, 0.75, s.r + (nz - 0.5) * 0.45);
	float sand_w = smoothstep(0.2, 0.8, s.b + (nz - 0.5) * 0.3);
	col = mix(col, dirt, dirt_w);
	col = mix(col, sand, sand_w);
	col = mix(col, moss, s.a * 0.8);
	vec3 rock = triplanar_tex(rock_tex, v_wp, n, rock_scale);
	// moss creeps over the top of rock faces
	rock = mix(rock, moss, smoothstep(0.55, 0.9, n.y) * 0.65);
	col = mix(col, rock, rock_w);
	// soft cavity darkening from the splat's rock channel and wetness
	col *= 1.0 - sand_w * 0.08;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, sand_w);
	SPECULAR = 0.3;
	if (rock_w > 0.01) {
		vec3 wn = triplanar_normal(rock_normal_tex, v_wp, n, rock_scale);
		vec3 vn = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, vn, rock_w));
	}
}
