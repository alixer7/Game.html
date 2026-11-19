shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Swirling goal portal drawn on a quad (billboarded by script).

uniform vec4 color_a : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.85, 0.3, 1.0, 1.0);
uniform float energy = 2.2;
uniform float locked = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float s1 = sin(a * 4.0 + r * 12.0 - TIME * 3.0) * 0.5 + 0.5;
	float s2 = sin(a * 7.0 - r * 18.0 + TIME * 4.5) * 0.5 + 0.5;
	float core = smoothstep(0.95, 0.0, r);
	float rim = smoothstep(0.76, 0.94, r) * (1.0 - smoothstep(0.94, 1.0, r));
	vec3 c = mix(color_a.rgb, color_b.rgb, s1);
	float lum = (s1 * 0.5 + s2 * 0.35 + 0.35) * core + rim * 1.8;
	ALBEDO = c * lum * energy * mix(1.0, 0.2, locked);
	ALPHA = clamp(lum, 0.0, 1.0);
}
