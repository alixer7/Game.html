shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// COLOR.r = style/4, COLOR.g = per-building seed, COLOR.b = window lit ratio, COLOR.a = 1 wall / 0 roof
// UV = (metres along facade, metres above ground) on walls
uniform sampler2DArray surf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float night = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float box2(vec2 f, vec2 lo, vec2 hi) {
	vec2 aa = fwidth(f) * 1.0;
	vec2 a = smoothstep(lo - aa, lo + aa, f) * (1.0 - smoothstep(hi - aa, hi + aa, f));
	return a.x * a.y;
}

void fragment() {
	int style = int(COLOR.r * 4.0 + 0.5);
	float seed = COLOR.g;
	vec3 wall_cols[4] = vec3[4](vec3(0.32, 0.36, 0.40), vec3(0.62, 0.60, 0.56), vec3(0.55, 0.30, 0.22), vec3(0.80, 0.80, 0.78));
	vec3 glass_cols[4] = vec3[4](vec3(0.10, 0.17, 0.24), vec3(0.12, 0.15, 0.16), vec3(0.08, 0.09, 0.1), vec3(0.11, 0.19, 0.2));
	vec3 wall = wall_cols[style] * mix(0.8, 1.2, fract(seed * 7.13));
	vec3 glass = glass_cols[style] * mix(0.8, 1.3, fract(seed * 3.71));
	float floor_h = style == 0 ? 3.9 : (style == 2 ? 3.1 : 3.6);
	float win_w = style == 0 ? 1.5 : (style == 2 ? 2.6 : 2.2);
	vec2 cell = vec2(UV.x / win_w, UV.y / floor_h);
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float win = 0.0;
	if (style == 0) {
		win = box2(f, vec2(0.05, 0.12), vec2(0.95, 0.96));
	} else if (style == 1) {
		win = box2(f, vec2(0.14, 0.28), vec2(0.86, 0.86));
	} else if (style == 2) {
		win = box2(f, vec2(0.28, 0.3), vec2(0.72, 0.85));
	} else {
		win = box2(f, vec2(0.0, 0.32), vec2(1.0, 0.8)) * (1.0 - box2(fract(UV.x / 7.0) * vec2(1.0), vec2(0.0), vec2(0.04)) );
	}
	// storefront on the ground floor
	if (id.y < 1.0) {
		win = box2(f, vec2(0.04, 0.05), vec2(0.96, 0.78));
		wall *= 0.6;
	}
	float h = hash12(id + seed * 113.0);
	vec3 wtex = texture(surf_albedo, vec3(UV * 0.25, style == 2 ? 5.0 : 3.0)).rgb;
	vec3 wall_col = wall * (wtex * 1.6);
	// blinds / interior variation
	vec3 g = glass * mix(0.7, 1.4, h);
	float blinds = step(0.82, h) * step(0.5, f.y);
	g = mix(g, vec3(0.55, 0.52, 0.45), blinds * 0.6);
	float lit = step(1.0 - COLOR.b, hash12(id * 1.7 + seed * 37.0));
	if (COLOR.a < 0.5) {
		// roof
		vec3 t = texture(surf_albedo, vec3(UV * 0.2, 3.0)).rgb;
		ALBEDO = t * vec3(0.75, 0.75, 0.76);
		ROUGHNESS = 0.9;
	} else {
		ALBEDO = mix(wall_col, g, win);
		METALLIC = win * 0.35;
		ROUGHNESS = mix(0.85, 0.06 + h * 0.08, win);
		SPECULAR = mix(0.4, 0.8, win);
		EMISSION = win * lit * vec3(1.0, 0.82, 0.55) * mix(0.15, 2.2, night) * mix(0.6, 1.2, h);
	}
}
