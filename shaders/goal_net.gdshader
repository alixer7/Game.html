shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Energy net lining the goals.
uniform vec3 team_color : source_color = vec3(0.1, 0.45, 1.0);
uniform float pulse = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * 2.4;
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	float e = 0.5 - max(q.x * 0.5 + q.y * 0.8660254, q.x);
	float line = 1.0 - smoothstep(0.0, 0.05 + fwidth(e) * 1.5, e);
	float wave = 0.5 + 0.5 * sin(wpos.y * 1.5 - TIME * 2.0);
	vec3 col = team_color * (0.25 + line * (1.2 + wave * 0.6 + pulse * 3.0));
	ALBEDO = col;
	ALPHA = clamp(0.12 + line * 0.55 + pulse * 0.3, 0.0, 1.0);
}
