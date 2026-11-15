shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.5;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = dot(p, p);
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.15, 1.0, d));
}
