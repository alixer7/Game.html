shader_type spatial;
render_mode cull_back;

uniform vec3 crust_color : source_color = vec3(0.14, 0.08, 0.09);
uniform vec3 magma_low : source_color = vec3(0.95, 0.22, 0.02);
uniform vec3 magma_hot : source_color = vec3(1.0, 0.84, 0.18);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 0.05 + TIME * 0.8) * cos(world_pos.z * 0.05 - TIME * 0.7) * 0.45;
}

void fragment() {
	vec2 p = world_pos.xz * 0.035;
	float t = TIME * 0.35;
	float c1 = sin(p.x * 3.0 + sin(p.y * 2.4 + t)) * cos(p.y * 2.8 - cos(p.x * 2.1 - t * 0.8));
	float c2 = sin((p.x + p.y) * 5.5 - t * 1.4) * 0.5 + 0.5;
	float flow = clamp(c1 * 0.5 + 0.5 + (c2 - 0.5) * 0.35, 0.0, 1.0);

	float vein = smoothstep(0.48, 0.82, flow);
	float core = smoothstep(0.76, 0.96, flow);
	vec3 col = mix(crust_color, magma_low, vein);
	col = mix(col, magma_hot, core);

	ALBEDO = col;
	EMISSION = mix(vec3(0.0), magma_low, vein) * 1.4 + magma_hot * core * 2.2;
	ROUGHNESS = mix(0.85, 0.25, vein);
}
