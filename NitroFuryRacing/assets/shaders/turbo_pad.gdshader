shader_type spatial;
render_mode cull_back;

uniform vec3 base_dark : source_color = vec3(0.08, 0.08, 0.12);
uniform vec3 main_glow : source_color = vec3(1.0, 0.46, 0.04);
uniform vec3 hot_glow : source_color = vec3(1.0, 0.94, 0.30);
uniform float scroll_speed = 2.6;

void fragment() {
	vec2 uv = UV;
	float dx = abs(uv.x - 0.5) * 2.0;
	float dy = abs(uv.y - 0.5) * 2.0;
	float frame_mask = max(step(0.88, dx), step(0.95, dy));
	float inner_rim = max(smoothstep(0.82, 0.88, dx), smoothstep(0.91, 0.95, dy)) * (1.0 - frame_mask);

	// Crisp forward-flowing CTR Plasma Chevrons!
	float chev = fract(uv.y * 4.2 + dx * 0.82 + TIME * scroll_speed);
	float band = smoothstep(0.24, 0.42, chev) * (1.0 - smoothstep(0.58, 0.72, chev));
	float core = smoothstep(0.40, 0.48, chev) * (1.0 - smoothstep(0.51, 0.60, chev));

	vec3 steel = vec3(0.16, 0.17, 0.21);
	vec3 col = mix(base_dark, main_glow, band * (1.0 - frame_mask));
	col = mix(col, hot_glow, max(core * (1.0 - frame_mask), inner_rim));
	col = mix(col, steel, frame_mask);

	float pulse = 0.90 + 0.10 * sin(TIME * 10.0);
	ALBEDO = col;
	EMISSION = (main_glow * band * 0.95 + hot_glow * max(core, inner_rim) * 1.45) * (1.0 - frame_mask) * pulse;
	METALLIC = mix(0.25, 0.85, frame_mask);
	ROUGHNESS = mix(0.28, 0.35, frame_mask);
}
