shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float speed = 1.4;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	// UV.x across (0..1), UV.y down the fall (0 at lip, 1 at pool)
	vec2 q = vec2(UV.x * 18.0, UV.y * 6.0 - TIME * speed);
	float streaks = vnoise(vec2(q.x * 2.0, q.y * 0.6)) * 0.6 + vnoise(vec2(q.x * 6.0, q.y * 1.5)) * 0.4;
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	float bottom = smoothstep(0.75, 1.0, UV.y);
	vec3 col = mix(vec3(0.55, 0.68, 0.72), vec3(0.95, 0.97, 0.98), smoothstep(0.35, 0.8, streaks) + bottom * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
	EMISSION = col * 0.08;
	ALPHA = clamp((0.45 + streaks * 0.55) * edge, 0.0, 0.95);
}
