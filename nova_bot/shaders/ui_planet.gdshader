shader_type canvas_item;
// Procedural planet used on the level-select cards (and as menu decoration).

uniform vec4 col_a : source_color = vec4(0.1, 0.6, 1.0, 1.0);
uniform vec4 col_b : source_color = vec4(0.5, 0.2, 0.9, 1.0);
uniform vec4 atmo : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform float seed = 1.0;
uniform float ring_amount = 0.0;
uniform float spin = 0.15;
uniform float locked = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	vec4 outc = vec4(0.0);
	if (r2 < 0.5) {
		vec2 q = p / 0.7071;
		float z = sqrt(max(0.0, 1.0 - dot(q, q)));
		vec3 n = vec3(q.x, -q.y, z);
		vec3 L = normalize(vec3(-0.55, 0.5, 0.65));
		float diff = clamp(dot(n, L), 0.0, 1.0);
		float lon = atan(n.x, n.z) + TIME * spin + seed;
		float band = sin(n.y * 7.0 + sin(lon * 3.0 + seed * 2.0) * 0.9 + seed) * 0.5 + 0.5;
		float swirl = sin(lon * 5.0 + n.y * 11.0 + seed) * 0.5 + 0.5;
		vec3 c = mix(col_a.rgb, col_b.rgb, band * 0.8 + swirl * 0.2);
		c *= 0.16 + diff * 1.0;
		float rim = pow(1.0 - z, 2.5);
		c += atmo.rgb * rim * 0.9 * (0.4 + diff);
		outc = vec4(c, 1.0);
	}
	float rr = sqrt(r2);
	float halo = exp(-max(rr - 0.7071, 0.0) * 8.0) * step(0.7071, rr) * 0.55;
	outc.rgb += atmo.rgb * halo;
	outc.a = max(outc.a, halo);
	if (ring_amount > 0.0) {
		float er = length(vec2(p.x, p.y * 3.4));
		float rv = smoothstep(0.98, 0.93, er) * smoothstep(0.74, 0.82, er);
		float front = (p.y > 0.0 || r2 > 0.5) ? 1.0 : 0.0;
		float k = rv * front * ring_amount;
		outc.rgb = mix(outc.rgb, atmo.rgb * 0.9, k);
		outc.a = max(outc.a, k * 0.9);
	}
	float lum = dot(outc.rgb, vec3(0.33));
	outc.rgb = mix(outc.rgb, vec3(lum) * 0.35, locked);
	COLOR = outc;
}
