shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec3 color_deep : source_color = vec3(0.06, 0.56, 0.88);
uniform vec3 color_foam : source_color = vec3(0.86, 0.98, 1.0);
uniform float flow_speed = 1.65;
uniform float alpha_base = 0.86;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * flow_speed;
	float streak1 = noise(vec2(uv.x * 14.0, uv.y * 5.0 - t * 2.2));
	float streak2 = noise(vec2(uv.x * 26.0 + 3.1, uv.y * 9.0 - t * 3.4));
	float foam = smoothstep(0.46, 0.84, streak1 * 0.65 + streak2 * 0.45);
	// Extra white splash foam at bottom & top crest!
	float edge_foam = smoothstep(0.78, 1.0, uv.y) + smoothstep(0.18, 0.0, uv.y);
	float f_total = clamp(foam + edge_foam * 0.75, 0.0, 1.0);
	ALBEDO = mix(color_deep, color_foam, f_total);
	// Soft tapered horizontal edges so waterfall blends cleanly against rock cliff!
	float side_fade = smoothstep(0.0, 0.14, uv.x) * smoothstep(1.0, 0.86, uv.x);
	ALPHA = alpha_base * side_fade;
}
