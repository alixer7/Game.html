shader_type spatial;
render_mode cull_back;

// Quarter-pipe between pitch and wall: turf fading into dark armoured panels
// with a glowing team-coloured rail at the top edge.
uniform vec3 grass : source_color = vec3(0.11, 0.36, 0.12);
uniform vec3 panel : source_color = vec3(0.06, 0.07, 0.10);
uniform vec3 blue_tint : source_color = vec3(0.10, 0.45, 1.0);
uniform vec3 orange_tint : source_color = vec3(1.0, 0.45, 0.05);
uniform float curve_r = 4.5;
uniform float half_len = 52.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float aa(float d, float w) {
	float fw = max(fwidth(d), 0.0001);
	return 1.0 - smoothstep(w - fw, w + fw, abs(d));
}

void fragment() {
	float h = wpos.y / curve_r;
	vec3 team = wpos.z > 0.0 ? blue_tint : orange_tint;
	float team_w = smoothstep(4.0, 30.0, abs(wpos.z));
	vec3 col = mix(grass, panel, smoothstep(0.15, 0.55, h));
	// panel seams running up the ramp
	float u = UV.x;
	float seam = aa(fract(u / 4.0) - 0.5, 0.012) * smoothstep(0.35, 0.6, h);
	col = mix(col, panel * 0.4, seam);
	// chevron stripes hint at the driving surface
	float chev = step(0.5, fract(u / 2.0 + h * 0.6)) * smoothstep(0.55, 0.75, h) * (1.0 - smoothstep(0.85, 0.95, h));
	col += team * chev * 0.05 * team_w;
	// glowing rail at the top of the ramp
	float rail = aa(h - 0.97, 0.025);
	vec3 rail_col = mix(vec3(0.85, 0.9, 1.0), team, team_w);
	col = mix(col, rail_col, rail);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.45, smoothstep(0.2, 0.6, h));
	METALLIC = mix(0.0, 0.4, smoothstep(0.2, 0.6, h));
	EMISSION = rail_col * rail * 2.2 + team * chev * 0.08 * team_w;
}
