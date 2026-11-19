shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Speed-pad / conveyor chevrons on a PlaneMesh. Chevrons flow toward local -Z.

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float energy = 2.2;
uniform float speed = 2.0;
uniform float density = 3.0;

void fragment() {
	vec2 p = UV;
	float x = abs(p.x - 0.5) * 2.0;
	float k = fract((1.0 - p.y) * density + x * 0.55 - TIME * speed);
	float band = smoothstep(0.0, 0.08, k) * (1.0 - smoothstep(0.28, 0.4, k));
	float border = smoothstep(0.88, 1.0, x) * 0.6 + smoothstep(0.95, 1.0, abs(p.y - 0.5) * 2.0) * 0.6;
	float a = clamp(band * (1.0 - x * 0.2) + border, 0.0, 1.0);
	ALBEDO = color.rgb * energy;
	ALPHA = a;
}
