shader_type spatial;
render_mode cull_back;

// Stylised turf with mowing stripes, team-tinted halves and glowing markings.
uniform vec3 grass_a : source_color = vec3(0.13, 0.42, 0.13);
uniform vec3 grass_b : source_color = vec3(0.10, 0.34, 0.11);
uniform vec3 blue_tint : source_color = vec3(0.10, 0.35, 1.0);
uniform vec3 orange_tint : source_color = vec3(1.0, 0.42, 0.05);
uniform vec3 line_color : source_color = vec3(0.92, 0.97, 1.0);
uniform float half_len = 52.0;
uniform float inset_x = 36.5;
uniform float inset_z = 47.5;
uniform float chamfer_k = 75.136;
uniform float goal_half_w = 8.9;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Anti-aliased line mask from a signed distance (meters).
float aa_line(float d, float w) {
	float fw = max(fwidth(d), 0.0001);
	return 1.0 - smoothstep(w - fw, w + fw, abs(d));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float ax = abs(p.x);
	float az = abs(p.y);
	bool in_goal = az > half_len;

	// Mowing stripes across the length of the pitch
	float stripe = step(0.5, fract(p.y / 13.0));
	vec3 col = mix(grass_a, grass_b, stripe);
	// grass grain
	float fw = fwidth(p.x) + fwidth(p.y);
	float grain = vnoise(p * 7.0) * 0.6 + vnoise(p * 23.0) * 0.4;
	grain = mix(grain, 0.5, clamp(fw * 4.0, 0.0, 1.0));
	col *= 0.86 + grain * 0.28;
	col *= 0.92 + 0.08 * vnoise(p * 0.25);

	// Team tint towards each end
	float side = clamp(p.y / half_len, -1.0, 1.0);
	vec3 tint = side > 0.0 ? blue_tint : orange_tint;
	col = mix(col, col * 0.55 + tint * 0.22, smoothstep(0.15, 1.0, abs(side)) * 0.55);

	// --- markings
	float lines = 0.0;
	float lw = 0.13;
	lines = max(lines, aa_line(p.y, lw) * step(ax, inset_x));                // halfway line
	lines = max(lines, aa_line(length(p) - 9.5, lw));                       // centre circle
	lines = max(lines, 1.0 - smoothstep(0.32, 0.36, length(p)));            // centre spot
	// Penalty boxes
	float box_front = inset_z - 8.0;
	lines = max(lines, aa_line(az - box_front, lw) * step(ax, 17.0));
	lines = max(lines, aa_line(ax - 17.0, lw) * step(box_front, az) * step(az, inset_z));
	// Arc in front of each box
	float arc = length(vec2(p.x, az - (inset_z - 2.0))) - 13.0;
	lines = max(lines, aa_line(arc, lw) * step(az, box_front));
	// Goal mouth line
	lines = max(lines, aa_line(az - inset_z, lw) * step(ax, goal_half_w));
	// Perimeter line where the quarter-pipe begins
	float s1 = ax - inset_x;
	float s3 = az - inset_z;
	float s2 = (ax + az - chamfer_k) * 0.70710678;
	float oct = max(s1, max(s2, s3));
	lines = max(lines, aa_line(oct + 0.6, lw) * (1.0 - step(abs(p.x), goal_half_w) * step(inset_z - 1.0, az)));

	// Centre emblem: hexagon ring and chevrons
	vec2 hp = abs(p);
	float hex = max(hp.x * 0.8660254 + hp.y * 0.5, hp.y) - 4.2;
	lines = max(lines, aa_line(hex, 0.22) * 0.8);
	vec2 cp = vec2(abs(p.x), p.y);
	float ch1 = abs(cp.y - (1.2 - cp.x * 0.9)) ;
	float ch2 = abs(cp.y - (-0.4 - cp.x * 0.9));
	float chevrons = (aa_line(ch1, 0.28) + aa_line(ch2, 0.28)) * step(cp.x, 2.2);
	vec3 emblem_col = mix(orange_tint, blue_tint, step(0.0, p.y));
	col = mix(col, emblem_col * 0.9, clamp(chevrons, 0.0, 1.0) * 0.75);

	col = mix(col, line_color, lines * 0.85);
	vec3 emis = line_color * lines * 0.28 + emblem_col * clamp(chevrons, 0.0, 1.0) * 0.35;

	if (in_goal) {
		// Goal interior: dark floor with a glowing grid in team colour
		vec3 gcol = side > 0.0 ? blue_tint : orange_tint;
		vec2 g = abs(fract(p * 0.5) - 0.5);
		float grid = 1.0 - smoothstep(0.02, 0.05, min(g.x, g.y));
		col = vec3(0.03, 0.035, 0.05) + gcol * grid * 0.25;
		emis = gcol * grid * 0.6;
	}

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	EMISSION = emis;
}
