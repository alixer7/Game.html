shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// UV.x = lateral metres, UV.y = metres downstream.
// COLOR.r = edge factor (1 at banks), COLOR.g = foam (rocks, rapids), COLOR.b = speed factor
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.32, 0.78, 0.78);
uniform vec3 deep_color : source_color = vec3(0.05, 0.36, 0.52);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform float flow_speed = 3.0;
uniform float alpha_center = 0.86;
uniform float alpha_edge = 0.55;
uniform float wave_height = 0.06;

void vertex() {
	float t = TIME;
	float sp = COLOR.b;
	VERTEX.y += sin(UV.y * 0.9 - t * flow_speed * 0.9 + UV.x * 0.7) * wave_height * (0.4 + sp)
		+ sin(UV.y * 2.3 - t * flow_speed * 1.7) * wave_height * 0.4 * COLOR.g;
}

void fragment() {
	float t = TIME;
	float sp = 0.5 + COLOR.b;
	vec2 uv1 = vec2(UV.x * 0.11, UV.y * 0.09 - t * flow_speed * 0.09 * sp);
	vec2 uv2 = vec2(UV.x * 0.23 + 0.37, UV.y * 0.17 - t * flow_speed * 0.15 * sp);
	vec3 n1 = texture(normal_tex, uv1).rgb;
	vec3 n2 = texture(normal_tex, uv2).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.9;
	float edge = clamp(COLOR.r, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, smoothstep(0.1, 1.0, edge));
	// foam: rocks/rapids painted in vertex colour + bank lapping
	float f1 = texture(foam_tex, vec2(UV.x * 0.25, UV.y * 0.2 - t * flow_speed * 0.2 * sp)).r;
	float f2 = texture(foam_tex, vec2(UV.x * 0.4 + 0.5, UV.y * 0.33 - t * flow_speed * 0.31 * sp)).r;
	float foam_mask = clamp(COLOR.g + smoothstep(0.82, 1.0, edge) * 0.8, 0.0, 1.0);
	float foam = smoothstep(0.35, 0.75, (f1 * 0.6 + f2 * 0.6) * foam_mask + foam_mask * 0.25);
	col = mix(col, foam_color, foam);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.5, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	ALPHA = mix(mix(alpha_center, alpha_edge, edge), 1.0, foam * 0.9);
}
