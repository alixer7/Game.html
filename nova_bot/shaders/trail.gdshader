shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Ribbon trail: colour and alpha come from vertex colours.

uniform float energy = 2.5;

void fragment() {
	ALBEDO = COLOR.rgb * energy;
	ALPHA = clamp(COLOR.a, 0.0, 1.0);
}
