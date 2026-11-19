shader_type spatial;
// Holographic (disappearing) platform: translucent body, bright edges, moving scan-lines.

uniform vec3 half_size = vec3(2.0, 0.5, 2.0);
uniform vec4 edge_color : source_color = vec4(0.7, 0.4, 1.0, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float warn = 0.0;

varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 d = half_size - abs(v_local);
	float m1 = min(d.x, min(d.y, d.z));
	float m3 = max(d.x, max(d.y, d.z));
	float mid = d.x + d.y + d.z - m1 - m3;
	float edge = 1.0 - smoothstep(0.03, 0.1, mid);
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	float scan = 0.5 + 0.5 * sin(v_world.y * 26.0 - TIME * 4.0 + v_world.x * 2.0);
	float blink = 1.0 - warn * (0.5 + 0.5 * sin(TIME * 30.0));
	ALBEDO = edge_color.rgb * 0.25;
	METALLIC = 0.0;
	ROUGHNESS = 0.4;
	EMISSION = edge_color.rgb * (edge * 3.2 + f * 0.9 + 0.35 * scan) * blink;
	ALPHA = clamp(0.2 + edge * 0.9 + f * 0.5 + 0.1 * scan, 0.0, 1.0) * fade;
}
