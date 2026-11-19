shader_type sky;
// Procedural space sky: gradient + nebula + galactic band + stars + giant planet + sun glow.
// No textures, no TIME (static radiance map => cheap ambient light).

uniform vec4 top_color : source_color = vec4(0.02, 0.03, 0.14, 1.0);
uniform vec4 mid_color : source_color = vec4(0.05, 0.16, 0.42, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.2, 0.65, 0.95, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.01, 0.02, 0.06, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.1, 0.5, 1.0, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.7, 0.2, 0.9, 1.0);
uniform float nebula_amount : hint_range(0.0, 2.0) = 1.0;
uniform float star_amount : hint_range(0.0, 2.0) = 1.0;
uniform vec3 sun_dir = vec3(0.4, 0.5, -0.75);
uniform vec4 sun_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform vec3 planet_dir = vec3(-0.55, 0.28, -0.8);
uniform float planet_size : hint_range(0.0, 0.5) = 0.16;
uniform vec4 planet_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 planet_color2 : source_color = vec4(0.8, 0.3, 0.9, 1.0);
uniform float seed = 1.0;
uniform float quality : hint_range(0.0, 1.0) = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float stars(vec3 d, float scale, float density, float sz) {
	vec3 p = d * scale;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash13(id + vec3(seed));
	if (h < density) {
		return 0.0;
	}
	vec3 off = vec3(hash13(id + 7.1), hash13(id + 13.7), hash13(id + 3.3)) - 0.5;
	float dist = length(f - off * 0.6);
	float b = smoothstep(sz, 0.0, dist);
	return b * (0.35 + 0.65 * hash13(id + 91.0));
}

float neb(vec3 d, float f, float s) {
	vec3 p = d * f + vec3(s);
	float v = sin(p.x * 1.7 + sin(p.y * 2.3 + sin(p.z * 1.9)));
	v += 0.5 * sin(p.y * 3.1 + sin(p.z * 2.7 + sin(p.x * 3.3)));
	v += 0.25 * sin(p.z * 6.3 + sin(p.x * 5.1 + sin(p.y * 4.7)));
	return clamp(v / 3.5 + 0.5, 0.0, 1.0);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color.rgb, mid_color.rgb, smoothstep(0.0, 0.32, h));
		col = mix(col, top_color.rgb, smoothstep(0.22, 0.95, h));
	} else {
		col = mix(horizon_color.rgb, bottom_color.rgb, smoothstep(0.0, 0.55, -h));
	}

	if (quality > 0.5) {
		// nebula clouds
		float n1 = neb(d, 1.6, seed);
		float n2 = neb(d, 2.5, seed * 3.1);
		float m = smoothstep(0.46, 0.86, n1);
		vec3 nc = mix(nebula_a.rgb, nebula_b.rgb, n2);
		float dust = smoothstep(0.55, 0.85, neb(d, 3.4, seed * 7.0));
		col *= 1.0 - dust * 0.35 * nebula_amount;
		col += nc * m * 0.75 * nebula_amount;

		// galactic band
		vec3 bn = normalize(vec3(0.25, 0.9, 0.15));
		float bd = dot(d, bn) * 3.2;
		float band = exp(-bd * bd);
		col += mix(nebula_a.rgb, vec3(1.0), 0.45) * band * 0.22 * nebula_amount * (0.6 + 0.4 * neb(d, 5.0, seed));
		// stars (two layers) – denser inside the band
		float st = stars(d, 70.0, 0.965, 0.14) * 1.4 + stars(d, 130.0, 0.97, 0.16) * 0.9;
		st += stars(d, 40.0, 0.985, 0.2) * 1.8 * band;
		col += vec3(0.85, 0.93, 1.0) * st * star_amount * smoothstep(-0.2, 0.15, h + 0.2);

		// giant planet
		vec3 pd = normalize(planet_dir);
		float ang = acos(clamp(dot(d, pd), -1.0, 1.0));
		if (planet_size > 0.001) {
			if (ang < planet_size) {
				vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), pd));
				vec3 u = cross(pd, r);
				vec2 q = vec2(dot(d, r), dot(d, u)) / sin(planet_size);
				float z = sqrt(max(0.0, 1.0 - dot(q, q)));
				vec3 n = normalize(r * q.x + u * q.y + pd * z);
				float lit = clamp(dot(n, normalize(sun_dir)) * 0.85 + 0.2, 0.05, 1.0);
				float bands = sin(q.y * 9.0 + sin(q.x * 3.0 + seed) * 0.8) * 0.5 + 0.5;
				vec3 pc = mix(planet_color.rgb, planet_color2.rgb, bands) * lit;
				pc += planet_color.rgb * pow(1.0 - z, 3.0) * 0.6;
				col = mix(col, pc, smoothstep(planet_size, planet_size * 0.97, ang));
			} else {
				col += planet_color.rgb * exp(-(ang - planet_size) * 28.0) * 0.35;
			}
		}
	}

	// sun glow
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_color.rgb * (pow(sd, 700.0) * 4.0 + pow(sd, 24.0) * 0.28);

	COLOR = col;
}
