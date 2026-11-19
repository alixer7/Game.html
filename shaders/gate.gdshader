shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform bool checker = false;
uniform vec3 color : source_color = vec3(1.0, 0.55, 0.12);

void fragment() {
	vec2 uv = UV;
	float edge = smoothstep(0.0, 0.06, uv.y) * smoothstep(1.0, 0.94, uv.y);
	vec3 c;
	float a;
	if (checker) {
		vec2 g = floor(vec2(uv.x * 24.0, uv.y * 4.0));
		float k = mod(g.x + g.y, 2.0);
		c = mix(vec3(0.05), vec3(1.0), k);
		a = 0.55;
	} else {
		// chevrons moving forward
		float x = abs(uv.x - 0.5) * 2.0;
		float ch = fract(uv.y * 2.0 + x * 0.8 - TIME * 1.2);
		float stripe = smoothstep(0.45, 0.5, ch) * (1.0 - smoothstep(0.75, 0.8, ch));
		c = color * (0.35 + stripe * 1.6);
		a = 0.35 + stripe * 0.4;
	}
	float side = smoothstep(0.0, 0.03, uv.x) * smoothstep(1.0, 0.97, uv.x);
	ALBEDO = c * edge * side * a * 1.8;
}
