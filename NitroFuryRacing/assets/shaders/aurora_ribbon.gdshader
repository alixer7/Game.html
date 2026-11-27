shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec3 color_a : source_color = vec3(0.08, 0.96, 0.62);
uniform vec3 color_b : source_color = vec3(0.22, 0.56, 1.0);
uniform vec3 color_c : source_color = vec3(0.66, 0.24, 1.0);

void vertex() {
	float wave = sin(VERTEX.x * 0.035 + TIME * 0.7) * 9.0 + cos(VERTEX.x * 0.07 - TIME * 0.45) * 4.5;
	VERTEX.z += wave;
}

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float curtain = sin(x * 24.0 + TIME * 0.9) * 0.5 + 0.5;
	float shimmer = sin(x * 52.0 - TIME * 1.4 + y * 5.0) * 0.5 + 0.5;
	float v_fade = smoothstep(0.0, 0.25, y) * smoothstep(1.0, 0.18, y);
	float h_fade = smoothstep(0.0, 0.15, x) * smoothstep(1.0, 0.85, x);
	vec3 col = mix(color_a, color_b, smoothstep(0.2, 0.75, y));
	col = mix(col, color_c, smoothstep(0.65, 1.0, y));
	float intensity = (0.35 + 0.65 * curtain * shimmer) * v_fade * h_fade;
	ALBEDO = col * intensity * 0.95;
	ALPHA = intensity * 0.65;
}
