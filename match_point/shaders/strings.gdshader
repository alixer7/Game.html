shader_type spatial;
render_mode cull_disabled;
// أوتار المضرب: شبكة داخل الإطار البيضاوي

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float inside = step(dot(p, p), 0.97);
	vec2 g = abs(fract(UV * vec2(16.0, 19.0)) - 0.5);
	float line = step(0.37, max(g.x, g.y));
	ALBEDO = vec3(0.93, 0.93, 0.86);
	ROUGHNESS = 0.5;
	ALPHA = inside * line;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
