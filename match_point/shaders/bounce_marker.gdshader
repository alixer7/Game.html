shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// مكان السقوط المتوقع للكرة (اختياري): علامة × ناعمة داخل دائرة باهتة
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.75);
uniform float alpha = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	vec2 q = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	float arm = min(abs(q.x), abs(q.y));
	float x = (1.0 - smoothstep(0.05, 0.10, arm)) * (1.0 - smoothstep(0.62, 0.72, d));
	float disc = (1.0 - smoothstep(0.80, 0.95, d)) * 0.22;
	float a = max(x, disc);
	ALBEDO = mix(vec3(0.03), color.rgb, x / max(a, 0.0001));
	ALPHA = a * alpha * color.a;
}
