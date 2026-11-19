shader_type spatial;
render_mode specular_schlick_ggx;
// Robot visor: glossy black glass with an animated LED face drawn as signed-distance shapes.
// mood: 0 normal, 1 happy ^^, 2 hurt ><, 3 determined, 4 sleepy / low power, 5 surprised O O, 6 dizzy spirals.

uniform vec4 eye_color : source_color = vec4(0.3, 0.92, 1.0, 1.0);
uniform float energy = 3.2;
uniform float open = 1.0;
uniform float mood = 0.0;
uniform vec2 look = vec2(0.0);
uniform float power = 1.0;
uniform float aspect = 1.6;
uniform float scan = 0.0;
uniform float squint = 0.0;

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_pill(vec2 p, float w, float h) {
	// vertical stadium of half width w, half height h
	float hh = max(h - w, 0.0);
	return length(vec2(p.x, max(abs(p.y) - hh, 0.0))) - w;
}

float eye(vec2 p, float side, int m) {
	if (m == 1) {
		// happy: upward arc
		vec2 q = p - vec2(0.0, -0.06);
		float r = length(q) - 0.17;
		float arc = abs(r) - 0.045;
		return max(arc, -q.y + 0.01);
	}
	if (m == 2) {
		// hurt: chevron > <
		float s = side;
		vec2 q = vec2(p.x * s, p.y);
		return min(sd_seg(q, vec2(-0.1, 0.13), vec2(0.08, 0.0)), sd_seg(q, vec2(-0.1, -0.13), vec2(0.08, 0.0))) - 0.045;
	}
	if (m == 3) {
		// determined: pill with a slanted lid
		float d = sd_pill(p, 0.085, 0.2 * open + 0.01);
		float lid = dot(p - vec2(0.0, 0.07), normalize(vec2(-0.45 * side, 1.0)));
		return max(d, lid);
	}
	if (m == 4) {
		// sleepy: low flat bar
		return sd_seg(p, vec2(-0.1, -0.03), vec2(0.1, -0.03)) - 0.04;
	}
	if (m == 5) {
		return abs(length(p) - 0.16) - 0.05;
	}
	if (m == 6) {
		float a = atan(p.y, p.x);
		float r = length(p);
		float sp = abs(fract((r * 9.0 - a / 6.2831853 + TIME * 2.0 * side)) - 0.5) / 9.0 - 0.02;
		return max(sp, r - 0.2);
	}
	float h = max(0.24 * open * (1.0 - squint * 0.45), 0.02);
	return sd_pill(p, 0.09, h);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0 * aspect, 2.0);
	p.y = -p.y;
	int m = int(mood + 0.5);
	vec2 lk = look * vec2(0.22, 0.14);
	float dl = eye(p - vec2(-0.5, 0.04) - lk, -1.0, m);
	float dr = eye(p - vec2(0.5, 0.04) - lk, 1.0, m);
	float d = min(dl, dr);
	float px = fwidth(d) * 1.2;
	float core = 1.0 - smoothstep(-px, px, d);
	float glow = exp(-max(d, 0.0) * 18.0) * 0.45;
	float lines = 0.86 + 0.14 * sin(UV.y * 140.0);
	float sweep = scan * smoothstep(0.08, 0.0, abs(UV.y - fract(TIME * 1.5)));
	float vig = smoothstep(1.25, 0.2, length(p / vec2(aspect, 1.0)));
	vec3 glass = vec3(0.008, 0.012, 0.024);
	ALBEDO = glass;
	METALLIC = 0.2;
	ROUGHNESS = 0.06;
	SPECULAR = 0.85;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.05;
	vec3 e = eye_color.rgb * energy * power * (core * lines + glow);
	e += eye_color.rgb * sweep * 0.8 * vig;
	EMISSION = e;
}
