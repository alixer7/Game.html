shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Additive glowing material with fresnel rim and optional scrolling stripes (UV.y).

uniform vec4 color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float energy = 2.0;
uniform float fresnel_pow = 2.0;
uniform float base_alpha = 0.15;
uniform float stripes = 0.0;
uniform float scroll_speed = 0.0;
uniform float alpha_mul = 1.0;

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), fresnel_pow);
	float s = 1.0;
	if (stripes > 0.5) {
		s = 0.55 + 0.45 * sin((UV.y * stripes - TIME * scroll_speed) * 6.2831);
	}
	float a = clamp((base_alpha + f) * s, 0.0, 1.0) * alpha_mul;
	ALBEDO = color.rgb * energy;
	ALPHA = a;
}
