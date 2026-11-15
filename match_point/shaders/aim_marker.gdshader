shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.84, 0.93, 0.22, 0.85);
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float ring = smoothstep(0.62, 0.70, d) * (1.0 - smoothstep(0.84, 0.92, d));
	float dot_c = 1.0 - smoothstep(0.10, 0.16, d);
	float cross_h = (1.0 - smoothstep(0.02, 0.05, abs(p.y))) * step(d, 0.62) * step(0.28, d);
	float cross_v = (1.0 - smoothstep(0.02, 0.05, abs(p.x))) * step(d, 0.62) * step(0.28, d);
	float a = max(max(ring, dot_c), max(cross_h, cross_v) * 0.7);
	ALBEDO = color.rgb;
	ALPHA = a * color.a * (0.8 + 0.2 * sin(pulse));
}
