shader_type spatial;
// Walkable platform surface with a per-world style. Works on (rounded) boxes and cylinders centred on the
// origin. style: 0 station metal panels + hazard trim, 1 crystal stone + glowing veins, 2 foundry tread
// plate + rust + heat, 3 snow over ice, 4 black glass with a gold hex grid. The accent colour (edge_color)
// outlines the rim so platform types stay readable.

uniform vec3 half_size = vec3(2.0, 0.5, 2.0);
uniform int style = 0;
uniform float cyl = 0.0;
uniform vec4 base_color : source_color = vec4(0.25, 0.28, 0.34, 1.0);
uniform vec4 top_color : source_color = vec4(0.55, 0.6, 0.68, 1.0);
uniform vec4 trim_color : source_color = vec4(1.0, 0.75, 0.15, 1.0);
uniform vec4 edge_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float edge_energy = 2.2;
uniform float crack = 0.0;
uniform float detail = 1.0;

varying vec3 v_local;
varying vec3 v_world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// distance to the closest cell border of a jittered grid (cheap voronoi edges)
float voro_edge(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash12(n + g), hash12(n + g + 17.3));
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return sqrt(d2) - sqrt(d1);
}

float hex_edge(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float top = smoothstep(0.55, 0.9, wn.y);
	float bottom = smoothstep(-0.55, -0.9, wn.y);
	// distance from the rim, measured in the top plane
	float rim_d;
	if (cyl > 0.5) {
		rim_d = half_size.x - length(v_local.xz);
	} else {
		rim_d = min(half_size.x - abs(v_local.x), half_size.z - abs(v_local.z));
	}
	float down = half_size.y - v_local.y;   // depth below the top face
	vec2 uv = v_world.xz;
	vec2 suv = vec2(v_world.x + v_world.z, v_world.y);
	vec3 alb;
	float rough = 0.5;
	float metal = 0.2;
	vec3 emis = vec3(0.0);
	float n1 = fbm(uv * 0.35);
	float n2 = vnoise(uv * 3.0);

	if (style == 1) {
		// crystal gardens: pale stone tiles, glowing crystal veins
		float ve = voro_edge(uv * 0.55);
		float vein = 1.0 - smoothstep(0.0, 0.07, ve);
		vec3 stone = mix(base_color.rgb, top_color.rgb, n1);
		alb = mix(stone * (0.8 + 0.2 * n2), top_color.rgb * 1.1, top * 0.35);
		alb = mix(alb, alb * 0.55, vein * top);
		emis += edge_color.rgb * vein * top * 0.9 * detail * (0.6 + 0.4 * sin(TIME * 1.5 + n1 * 8.0));
		float strata = smoothstep(0.4, 0.6, fract(v_world.y * 1.6 + n1 * 0.6));
		alb = mix(alb, alb * 0.75, strata * (1.0 - top) * 0.6);
		rough = 0.6;
		metal = 0.0;
	} else if (style == 2) {
		// foundry: diamond tread plate, rust, heat at the rim
		vec2 d = vec2(uv.x + uv.y, uv.x - uv.y) * 2.2;
		vec2 c = fract(d) - 0.5;
		float bump = smoothstep(0.32, 0.18, abs(c.x) + abs(c.y) * 2.4);
		float rust = smoothstep(0.55, 0.82, fbm(uv * 0.45 + 4.0));
		alb = mix(base_color.rgb, top_color.rgb, top) * (0.85 + 0.25 * bump * top);
		alb = mix(alb, vec3(0.42, 0.2, 0.08), rust * 0.75);
		rough = mix(0.35, 0.85, rust);
		metal = mix(0.85, 0.2, rust);
		float rivet = smoothstep(0.07, 0.04, length(fract(suv * vec2(1.4, 2.5)) - 0.5));
		alb = mix(alb, alb * 1.4, rivet * (1.0 - top));
		emis += trim_color.rgb * smoothstep(0.6, 0.0, down) * (1.0 - top) * 0.6;
	} else if (style == 3) {
		// ice comet: snow on top, glassy blue ice on the sides
		float snow_edge = smoothstep(0.0, 0.25 + n2 * 0.25, down);
		float snow = top + (1.0 - snow_edge) * (1.0 - top);
		vec3 ice = mix(base_color.rgb, base_color.rgb * 1.6, fbm(suv * 0.8));
		float cr = 1.0 - smoothstep(0.0, 0.05, voro_edge(suv * 0.9));
		ice += vec3(0.6, 0.85, 1.0) * cr * 0.25;
		vec3 snowc = top_color.rgb * (0.86 + 0.1 * n2) * mix(vec3(0.82, 0.9, 1.0), vec3(1.0), smoothstep(0.3, 0.7, n1));
		alb = mix(ice, snowc, clamp(snow, 0.0, 1.0));
		rough = mix(0.08, 0.75, snow);
		metal = 0.0;
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		emis += base_color.rgb * fres * 0.6 * (1.0 - snow);
		float tw = 0.5 + 0.5 * sin(TIME * 4.0 + hash12(floor(uv * 22.0)) * 40.0 + dot(VIEW, vec3(7.0)));
		float glint = step(0.985, hash12(floor(uv * 22.0))) * tw;
		emis += vec3(1.0) * glint * top * 2.0 * detail;
	} else if (style == 4) {
		// galaxy core: black glass with gold hex lines and star sparkle
		float he = hex_edge(uv * 0.9);
		float line = 1.0 - smoothstep(0.0, 0.035, he);
		alb = mix(base_color.rgb, top_color.rgb, top * 0.5 + n1 * 0.3);
		alb = mix(alb, trim_color.rgb * 0.6, line * top);
		emis += trim_color.rgb * line * top * 0.7 * detail;
		float star = step(0.992, hash12(floor(uv * 14.0))) * (0.5 + 0.5 * sin(TIME * 3.0 + hash12(floor(uv * 14.0)) * 30.0));
		emis += vec3(0.8, 0.85, 1.0) * star * top * 1.5 * detail;
		float band = smoothstep(0.03, 0.0, abs(fract(v_world.y * 1.2) - 0.5) - 0.42);
		emis += trim_color.rgb * band * (1.0 - top) * 0.5;
		rough = 0.12;
		metal = 0.6;
	} else {
		// launch station: brushed metal panels, bolts, hazard-striped trim
		vec2 pc = uv / 2.0;
		vec2 pf = fract(pc);
		vec2 pid = floor(pc);
		float seam = 1.0 - smoothstep(0.0, 0.025, min(min(pf.x, 1.0 - pf.x), min(pf.y, 1.0 - pf.y)));
		float tint = hash12(pid) * 0.12;
		alb = mix(base_color.rgb, top_color.rgb, top) * (0.92 + tint) * (0.94 + 0.06 * vnoise(uv * vec2(18.0, 1.5)));
		alb = mix(alb, alb * 0.45, seam * top);
		vec2 bc = abs(pf - 0.5);
		float bolt = smoothstep(0.035, 0.02, length(bc - vec2(0.42)));
		alb = mix(alb, alb * 1.35, bolt * top);
		float groove = smoothstep(0.03, 0.0, abs(fract(down * 2.0) - 0.5) - 0.45);
		alb = mix(alb, alb * 0.6, groove * (1.0 - top));
		float lights = step(0.5, fract(suv.x * 0.5)) * smoothstep(0.06, 0.0, abs(down - half_size.y));
		emis += edge_color.rgb * lights * (1.0 - top) * 0.8;
		rough = 0.38;
		metal = 0.65;
	}

	// trim band around the top rim
	float band_w = (style == 0) ? 0.34 : 0.18;
	float in_band = top * (1.0 - smoothstep(band_w - 0.02, band_w, rim_d)) * step(1.2, min(half_size.x, half_size.z));
	if (style == 0) {
		float stripe = step(0.5, fract((v_world.x + v_world.z) * 1.4));
		alb = mix(alb, mix(vec3(0.05), trim_color.rgb, stripe), in_band);
		rough = mix(rough, 0.5, in_band);
		metal = mix(metal, 0.1, in_band);
	} else if (style == 4 || style == 2) {
		alb = mix(alb, trim_color.rgb * 0.8, in_band);
		metal = mix(metal, 1.0, in_band);
		rough = mix(rough, 0.25, in_band);
	} else if (style == 3) {
		alb = mix(alb, vec3(0.85, 0.95, 1.0), in_band * 0.5);
	}

	// accent rim line (platform type colour)
	float rl = 1.0 - smoothstep(0.03, 0.09, abs(rim_d - 0.06));
	float glow_line = rl * top + (1.0 - smoothstep(0.03, 0.08, abs(down - 0.1))) * (1.0 - top) * (1.0 - bottom);
	emis += edge_color.rgb * glow_line * edge_energy * (0.85 + 0.15 * sin(TIME * 2.0 + v_world.x * 0.3 + v_world.z * 0.3));

	// cracks (crumbling platforms)
	if (crack > 0.0) {
		float ce = 1.0 - smoothstep(0.0, 0.05, voro_edge(uv * 1.3 + 3.0));
		alb = mix(alb, alb * 0.35, ce * crack);
		emis += edge_color.rgb * ce * crack * 0.8;
	}
	alb *= mix(1.0, 0.55, bottom);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
}
