shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque;

uniform vec3 color_a : source_color = vec3(1.0, 0.55, 0.1);
uniform vec3 color_b : source_color = vec3(1.0, 0.92, 0.4);
uniform float speed = 1.6;

void fragment() {
	// UV.y runs along the pad (PlaneMesh: -Z = UV.y 0). Chevrons scroll forward.
	vec2 uv = UV;
	float x = abs(uv.x - 0.5) * 2.0;
	float v = fract((1.0 - uv.y) * 3.0 + TIME * speed - x * 0.45);
	float chev = smoothstep(0.0, 0.08, v) * (1.0 - smoothstep(0.45, 0.55, v));
	float border = step(0.88, x) + step(0.96, abs(uv.y - 0.5) * 2.0);
	vec3 base = mix(color_a * 0.35, color_a, chev);
	base = mix(base, color_b, clamp(border, 0.0, 1.0) * 0.8);
	ALBEDO = base * 1.6;
	EMISSION = base * 0.8;
}
