shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// Transparent stadium wall: tinted glass with a hexagonal frame grid,
// an animated LED advertising band and team-coloured halves.
uniform vec3 blue_tint : source_color = vec3(0.10, 0.45, 1.0);
uniform vec3 orange_tint : source_color = vec3(1.0, 0.45, 0.05);
uniform float height = 20.5;
uniform float curve_r = 4.5;
uniform float is_top = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(q.x * 0.5 + q.y * 0.8660254, q.x);
}

void fragment() {
	float side = clamp(wpos.z / 30.0, -1.0, 1.0);
	vec3 team = mix(orange_tint, blue_tint, side * 0.5 + 0.5);
	vec2 uv = vec2(UV.x, wpos.y) / 3.2;
	float e = hex_edge(uv);
	float fw = fwidth(e) * 1.5;
	float grid = 1.0 - smoothstep(0.0, 0.025 + fw, e);
	float y = wpos.y;
	// LED band just above the ramp
	float band = step(curve_r + 0.25, y) * step(y, curve_r + 1.45) * (1.0 - is_top);
	float scroll = fract(UV.x / 24.0 - TIME * 0.05);
	float led = 0.55 + 0.45 * sin(scroll * 6.2831 * 3.0 + y * 2.0);
	float chevrons = step(0.5, fract(UV.x / 3.0 + abs(y - curve_r - 0.85) * 0.5 - TIME * 0.6));
	vec3 band_col = team * (0.6 + 0.4 * chevrons) * led;
	// vertical fade: stronger glass near the bottom
	float fade = 1.0 - smoothstep(curve_r, height, y);
	vec3 glass = vec3(0.35, 0.5, 0.75) * 0.06 + team * 0.04;
	vec3 col = glass + team * grid * (0.5 + 0.4 * fade);
	float alpha = 0.06 + 0.08 * fade + grid * (0.18 + 0.25 * fade);
	// edge rail at the top of each wall
	float top_rail = smoothstep(0.12, 0.0, abs(y - (height - curve_r))) * (1.0 - is_top);
	col += team * top_rail * 0.8;
	alpha = max(alpha, top_rail * 0.45);
	col = mix(col, band_col * 1.6, band);
	alpha = mix(alpha, 0.92, band);
	if (is_top > 0.5) {
		alpha *= 0.55;
	}
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
