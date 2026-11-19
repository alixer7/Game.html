shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
// Swirling accretion disk / energy ring on a flat annulus (UV.x = angle 0..1, UV.y = radius 0..1 from Geo.lathe).

uniform vec4 inner : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform vec4 outer : source_color = vec4(0.55, 0.3, 1.0, 1.0);
uniform float energy = 2.0;
uniform float speed = 0.05;

void fragment() {
	float r = UV.y;
	float a = UV.x * 6.2831853;
	float t = TIME * speed;
	float swirl = 0.5 + 0.5 * sin(a * 9.0 - r * 30.0 + t * 40.0);
	float swirl2 = 0.5 + 0.5 * sin(a * 23.0 + r * 55.0 - t * 70.0);
	float band = smoothstep(0.0, 0.12, r) * (1.0 - smoothstep(0.6, 1.0, r));
	vec3 c = mix(inner.rgb, outer.rgb, smoothstep(0.05, 0.8, r));
	float k = band * (0.45 + 0.4 * swirl + 0.25 * swirl2);
	ALBEDO = c * energy * k;
	ALPHA = clamp(k, 0.0, 1.0);
}
