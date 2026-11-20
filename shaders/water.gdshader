shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// ماء شفاف بأمواج متحركة وانعكاس فرينل
uniform vec3 deep_color : source_color = vec3(0.03, 0.15, 0.22);
uniform vec3 shallow_color : source_color = vec3(0.1, 0.34, 0.38);
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wave_speed = 0.025;
uniform float alpha_val = 0.8;
uniform float storm = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = 0.05 + storm * 0.12;
	VERTEX.y += sin(wpos.x * 0.15 + TIME * 0.9) * amp + cos(wpos.z * 0.12 + TIME * 0.7) * amp;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.035 + vec2(TIME * wave_speed, TIME * wave_speed * 0.6);
	vec2 uv2 = wpos.xz * 0.1 - vec2(TIME * wave_speed * 0.8, -TIME * wave_speed * 1.1);
	vec3 n1 = texture(normal_a, uv1).rgb;
	vec3 n2 = texture(normal_b, uv2).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.55 + storm * 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(shallow_color, deep_color, 0.55 + fres * 0.3);
	ALPHA = mix(alpha_val, 0.97, fres);
	ROUGHNESS = 0.05 + storm * 0.1;
	METALLIC = 0.0;
	SPECULAR = 0.75;
}
