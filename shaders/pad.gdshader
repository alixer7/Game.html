shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Additive glow used for boost pads (ring + disc), driven by `active`.
uniform vec3 color : source_color = vec3(1.0, 0.65, 0.1);
uniform float active = 1.0;
uniform float big = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.08, 0.0, abs(r - 0.82));
	float disc = (1.0 - smoothstep(0.0, 0.8, r)) * 0.9;
	float spokes = step(0.85, fract(atan(p.y, p.x) / 6.2831 * 6.0 + TIME * 0.3)) * step(r, 0.75) * step(0.35, r);
	float pulse = 0.75 + 0.25 * sin(TIME * 4.0);
	float a = (ring * 1.2 + disc * pulse + spokes * 0.5 * big) * mix(0.15, 1.0, active);
	if (r > 1.0) { a = 0.0; }
	ALBEDO = color * a * 2.4;
	ALPHA = clamp(a, 0.0, 1.0);
}
