shader_type spatial;
render_mode specular_schlick_ggx;
// Energy cell: glass tube whose glowing fill shows the charge level (UV.y = 0 bottom .. 1 top on a lathe mesh).

uniform float level : hint_range(0.0, 1.0) = 1.0;
uniform vec4 full_color : source_color = vec4(0.25, 1.0, 0.55, 1.0);
uniform vec4 low_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float energy = 3.0;
uniform float segments = 5.0;
uniform float blink = 0.0;
uniform float charge_wave = 0.0;
uniform float y0 = 0.08;
uniform float y1 = 0.92;

void fragment() {
	float v = clamp((UV.y - y0) / (y1 - y0), 0.0, 1.0);
	float inside = step(y0, UV.y) * step(UV.y, y1);
	vec3 col = mix(low_color.rgb, full_color.rgb, smoothstep(0.15, 0.6, level));
	float seg = fract(v * segments);
	float gap = smoothstep(0.0, 0.06, seg) * smoothstep(1.0, 0.94, seg);
	float filled = step(v, level);
	float bubbles = 0.75 + 0.25 * sin(v * 40.0 - TIME * 6.0 + UV.x * 25.0);
	float bl = 1.0 - blink * (0.5 + 0.5 * sin(TIME * 18.0));
	float wave = charge_wave * smoothstep(0.12, 0.0, abs(v - fract(TIME * 1.8)));
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = mix(vec3(0.03, 0.04, 0.06), col * 0.25, filled * inside);
	METALLIC = 0.1;
	ROUGHNESS = 0.12;
	CLEARCOAT = 1.0;
	EMISSION = col * energy * inside * (filled * gap * bubbles * bl + wave) + col * fres * 0.4 * inside;
}
