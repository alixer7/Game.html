shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.04, 0.72, 0.78);
uniform vec3 deep_color : source_color = vec3(0.02, 0.28, 0.56);
uniform vec3 foam_color : source_color = vec3(0.86, 0.98, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w1 = sin(world_pos.x * 0.09 + TIME * 1.4) * cos(world_pos.z * 0.08 + TIME * 1.1);
	float w2 = sin((world_pos.x + world_pos.z) * 0.16 - TIME * 2.0);
	VERTEX.y += (w1 * 0.35 + w2 * 0.18);
}

void fragment() {
	vec2 p = world_pos.xz * 0.055;
	float t = TIME * 0.75;
	float w_a = sin(p.x * 3.1 + t * 1.6) * cos(p.y * 2.8 - t * 1.3);
	float w_b = sin((p.x - p.y) * 5.2 + t * 2.1);
	float w_c = cos((p.x * 0.7 + p.y * 1.3) * 8.5 - t * 2.4);
	float wave = w_a * 0.5 + w_b * 0.32 + w_c * 0.18;

	// Analytical normal perturbation for sparkling sun reflections!
	vec3 n = normalize(vec3(
		cos(p.x * 3.1 + t * 1.6) * 0.14 + cos((p.x - p.y) * 5.2 + t * 2.1) * 0.10,
		1.0,
		-sin(p.y * 2.8 - t * 1.3) * 0.14 - cos((p.x - p.y) * 5.2 + t * 2.1) * 0.10
	));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep_color, shallow_color, clamp(0.45 + wave * 0.45 + fresnel * 0.4, 0.0, 1.0));
	float caustic = smoothstep(0.62, 0.88, wave);
	col = mix(col, foam_color, caustic * 0.55);

	ALBEDO = col;
	ROUGHNESS = 0.16;
	METALLIC = 0.08;
	SPECULAR = 0.75;
}
