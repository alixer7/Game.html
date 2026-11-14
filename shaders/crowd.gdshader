shader_type spatial;
render_mode cull_disabled;

// Procedural crowd on the stands: seat rows with randomly coloured fans that
// bounce when excited, plus occasional camera flashes.
uniform float excitement = 0.0;
uniform vec3 blue_tint : source_color = vec3(0.10, 0.45, 1.0);
uniform vec3 orange_tint : source_color = vec3(1.0, 0.45, 0.05);

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell_size = vec2(0.75, 0.95);
	vec2 uv = UV / cell_size;
	vec2 id = floor(uv);
	vec2 f = fract(uv);
	float r = hash(id);
	float r2 = hash(id + 17.3);
	float jump = excitement * max(0.0, sin(TIME * (6.0 + r * 5.0) + r * 30.0)) * 0.25;
	vec2 q = f - vec2(0.5, 0.35 + jump);
	float body = step(abs(q.x), 0.28) * step(q.y, 0.18) * step(-0.35, q.y);
	float head = 1.0 - step(0.15, length(q - vec2(0.0, 0.32)));
	float person = max(body, head) * step(0.12, r2);
	vec3 fan = r < 0.4 ? blue_tint : (r < 0.8 ? orange_tint : vec3(0.85));
	fan *= 0.55 + 0.6 * r2;
	vec3 seat = vec3(0.09, 0.1, 0.13) * (0.8 + 0.4 * step(0.5, fract(id.y * 0.5)));
	vec3 col = mix(seat, fan, person);
	// distance-based blur to avoid shimmering
	float fw = fwidth(uv.x) + fwidth(uv.y);
	col = mix(col, mix(seat, fan, 0.45), clamp(fw * 1.5, 0.0, 1.0));
	float flash = step(0.9985 - excitement * 0.003, hash(id + floor(TIME * 8.0)));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = vec3(1.0) * flash * 2.0 + fan * person * 0.22 + seat * 0.3;
}
