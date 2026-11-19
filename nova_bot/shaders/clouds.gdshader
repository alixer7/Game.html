shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// Sea far below the platforms (follows the camera, pattern anchored in world space):
// mode 0 clouds, 1 molten lava, 2 icy mist, 3 swirling void / galaxy.

uniform int mode = 0;
uniform vec4 col_a : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform vec4 col_b : source_color = vec4(0.1, 0.15, 0.35, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float fade_dist = 420.0;
uniform vec2 center_xz = vec2(0.0);
uniform vec2 swirl_center = vec2(0.0);

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
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += vnoise(p) * a;
		p = p * 2.02 + vec2(5.3, 1.7);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz * 0.012;
	float t = TIME;
	float d = length(v_world.xz - center_xz);
	float fade = 1.0 - smoothstep(fade_dist * 0.25, fade_dist, d);
	vec3 col;
	float a = 1.0;
	if (mode == 1) {
		float n = fbm(p * 2.5 + vec2(t * 0.02, -t * 0.015));
		float cr = 1.0 - abs(fbm(p * 5.0 - vec2(t * 0.03, 0.0)) * 2.0 - 1.0);
		float hot = smoothstep(0.75, 0.98, cr) + smoothstep(0.55, 0.9, n) * 0.5;
		col = mix(col_b.rgb, col_a.rgb, n) + glow.rgb * hot * (1.5 + 0.5 * sin(t * 1.5 + n * 6.0));
	} else if (mode == 3) {
		vec2 q = v_world.xz - swirl_center;
		float r = length(q) * 0.01;
		float ang = atan(q.y, q.x);
		float arms = sin(ang * 3.0 - log(r + 0.05) * 6.0 + t * 0.15) * 0.5 + 0.5;
		float n = fbm(vec2(ang * 2.0, r * 4.0) + t * 0.02);
		col = mix(col_b.rgb, col_a.rgb, arms * n * 1.4) + glow.rgb * pow(arms * n, 4.0) * 3.0;
		col += vec3(1.0) * step(0.997, hash12(floor(v_world.xz * 0.6))) * 1.5;
	} else {
		vec2 w = vec2(t * 0.012, t * 0.007);
		float n = fbm(p * 1.6 + w);
		float n2 = fbm(p * 4.0 - w * 1.7 + n);
		float cloud = smoothstep(0.3, 0.75, n * 0.7 + n2 * 0.5);
		col = mix(col_b.rgb, col_a.rgb, cloud);
		col += glow.rgb * pow(cloud, 3.0) * 0.35;
		if (mode == 2) {
			col += vec3(0.6, 0.8, 1.0) * step(0.996, hash12(floor(v_world.xz * 0.8))) * 0.8;
		}
	}
	ALBEDO = col;
	ALPHA = a * fade;
}
