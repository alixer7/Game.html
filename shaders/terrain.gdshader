shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Splat: R rock, G sand, B dirt/forest floor, A snow. Grass = remainder.
uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float world_half = 2048.0;
uniform float tile_near = 0.16;      // texture repeats per metre
uniform float tile_far = 0.035;
uniform int quality = 1;             // 0 low, 1 medium, 2 high
uniform vec3 grass_tint : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

// sample one layer with two scales to hide tiling
void layer(int idx, vec2 p, float far_mix, inout vec4 alb, inout vec3 nrm, float w) {
	if (w < 0.004) return;
	vec4 a = texture(albedo_tex, vec3(p * tile_near, float(idx)));
	vec3 n = texture(normal_tex, vec3(p * tile_near, float(idx))).rgb;
	if (quality > 0) {
		vec4 a2 = texture(albedo_tex, vec3(p * tile_far + vec2(0.37, 0.71), float(idx)));
		vec3 n2 = texture(normal_tex, vec3(p * tile_far + vec2(0.37, 0.71), float(idx))).rgb;
		a = mix(a, a2, far_mix);
		n = mix(n, n2, far_mix * 0.7);
	}
	alb += a * w;
	nrm += n * w;
}

void fragment() {
	vec2 uv = (v_world.xz + world_half) / (world_half * 2.0);
	vec4 s = texture(splat, uv);
	float macro = vnoise(v_world.xz * 0.012) * 0.6 + vnoise(v_world.xz * 0.05) * 0.4;
	float detail = vnoise(v_world.xz * 0.35);
	float slope = 1.0 - clamp(v_wn.y, 0.0, 1.0);
	// sharpen transitions with noise for natural edges
	float rock = clamp(s.r + (macro - 0.5) * 0.25 + (detail - 0.5) * 0.15, 0.0, 1.0);
	rock = max(rock, smoothstep(0.42, 0.62, slope));
	float sand = clamp(s.g + (detail - 0.5) * 0.2, 0.0, 1.0) * (1.0 - rock);
	float dirt_all = clamp(s.b + (detail - 0.5) * 0.25, 0.0, 1.0) * (1.0 - rock) * (1.0 - sand);
	float snow = clamp(s.a + (macro - 0.5) * 0.3, 0.0, 1.0);
	snow = snow * (1.0 - smoothstep(0.55, 0.75, slope));
	float forest = dirt_all * smoothstep(0.35, 0.65, macro);
	float dirt = dirt_all - forest;
	float grass = clamp(1.0 - rock - sand - dirt - forest, 0.0, 1.0);
	float total = grass + rock + sand + dirt + forest + 0.0001;
	grass /= total; rock /= total; sand /= total; dirt /= total; forest /= total;

	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float far_mix = mix(0.35, 0.85, smoothstep(30.0, 220.0, dist));

	vec4 alb = vec4(0.0);
	vec3 nrm = vec3(0.0);
	vec2 p = v_world.xz;
	layer(0, p, far_mix, alb, nrm, grass);
	layer(2, p, far_mix, alb, nrm, sand);
	layer(3, p, far_mix, alb, nrm, dirt);
	layer(5, p, far_mix, alb, nrm, forest);
	if (rock > 0.004) {
		// tri-planar rock so cliffs are not stretched
		vec3 bw = pow(abs(v_wn), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec4 ra = vec4(0.0);
		vec3 rn = vec3(0.0);
		float rs = 0.045;
		if (quality > 0) {
			ra += texture(albedo_tex, vec3(v_world.zy * rs, 1.0)) * bw.x;
			rn += texture(normal_tex, vec3(v_world.zy * rs, 1.0)).rgb * bw.x;
			ra += texture(albedo_tex, vec3(v_world.xz * rs, 1.0)) * bw.y;
			rn += texture(normal_tex, vec3(v_world.xz * rs, 1.0)).rgb * bw.y;
			ra += texture(albedo_tex, vec3(v_world.xy * rs, 1.0)) * bw.z;
			rn += texture(normal_tex, vec3(v_world.xy * rs, 1.0)).rgb * bw.z;
		} else {
			ra = texture(albedo_tex, vec3(v_world.xz * rs, 1.0));
			rn = texture(normal_tex, vec3(v_world.xz * rs, 1.0)).rgb;
		}
		alb += ra * rock;
		nrm += rn * rock;
	}
	// snow on top
	if (snow > 0.004) {
		vec4 sa = texture(albedo_tex, vec3(p * tile_near * 0.7, 4.0));
		vec3 sn = texture(normal_tex, vec3(p * tile_near * 0.7, 4.0)).rgb;
		alb = mix(alb, sa, snow);
		nrm = mix(nrm, sn, snow);
	}
	vec3 col = alb.rgb;
	// macro colour variation (patches of dry / lush grass)
	col *= mix(vec3(0.92, 0.95, 0.88), vec3(1.08, 1.04, 0.96), macro);
	col = mix(col, col * grass_tint, grass);
	ALBEDO = col;
	ROUGHNESS = clamp(alb.a, 0.3, 1.0);
	SPECULAR = 0.35;
	NORMAL_MAP = normalize(nrm * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(1.0, 0.35, smoothstep(40.0, 300.0, dist));
}
