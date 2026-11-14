shader_type spatial;

// Truncated-icosahedron panel pattern (12 pentagons + 20 hexagons) computed
// in object space, with glowing seams that flare when the ball is struck.
uniform vec3 panel_a : source_color = vec3(0.92, 0.94, 0.97);
uniform vec3 panel_b : source_color = vec3(0.16, 0.18, 0.24);
uniform vec3 seam_color : source_color = vec3(0.35, 0.85, 1.0);
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 lpos;

void vertex() {
	lpos = normalize(VERTEX);
}

void fragment() {
	// Icosahedron vertices (pentagon centres) and face centres (hexagons)
	float t = 1.6180339;
	vec3 iv[12] = vec3[](
		vec3(-1.0, t, 0.0), vec3(1.0, t, 0.0), vec3(-1.0, -t, 0.0), vec3(1.0, -t, 0.0),
		vec3(0.0, -1.0, t), vec3(0.0, 1.0, t), vec3(0.0, -1.0, -t), vec3(0.0, 1.0, -t),
		vec3(t, 0.0, -1.0), vec3(t, 0.0, 1.0), vec3(-t, 0.0, -1.0), vec3(-t, 0.0, 1.0));
	vec3 p = normalize(lpos);
	float best = -2.0;
	float second = -2.0;
	bool pent = false;
	for (int i = 0; i < 12; i++) {
		float d = dot(p, normalize(iv[i])) * 0.982; // bias sizes the pentagons
		if (d > best) { second = best; best = d; pent = true; }
		else if (d > second) { second = d; }
	}
	// Face centres = normalised sums of icosahedron face triples (20 faces)
	int faces[60] = int[](0,11,5, 0,5,1, 0,1,7, 0,7,10, 0,10,11, 1,5,9, 5,11,4, 11,10,2, 10,7,6, 7,1,8,
		3,9,4, 3,4,2, 3,2,6, 3,6,8, 3,8,9, 4,9,5, 2,4,11, 6,2,10, 8,6,7, 9,8,1);
	for (int f = 0; f < 20; f++) {
		vec3 c = normalize(iv[faces[f * 3]] + iv[faces[f * 3 + 1]] + iv[faces[f * 3 + 2]]);
		float d = dot(p, c);
		if (d > best) { second = best; best = d; pent = false; }
		else if (d > second) { second = d; }
	}
	float edge = best - second;
	float fw = fwidth(edge) * 1.2;
	float seam = 1.0 - smoothstep(0.004, 0.012 + fw, edge);
	vec3 col = pent ? panel_b : panel_a;
	col = mix(col, seam_color * 0.4, seam);
	ALBEDO = col;
	ROUGHNESS = pent ? 0.35 : 0.25;
	METALLIC = 0.15;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = seam_color * seam * (0.9 + flash * 3.0) + flash_color * flash * 0.45 + vec3(0.6, 0.75, 1.0) * rim * 0.25;
}
