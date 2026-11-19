shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Expanding shock-wave ring drawn on a quad. Animate `progress` from 0 to 1.

uniform vec4 color : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float width = 0.2;
uniform float energy = 3.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float rr = mix(0.08, 1.0, 1.0 - pow(1.0 - progress, 2.5));
	float ring = smoothstep(rr - width, rr, r) * (1.0 - smoothstep(rr, rr + 0.025, r));
	float fade = 1.0 - progress;
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(ring * fade, 0.0, 1.0);
}
