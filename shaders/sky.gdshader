shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.16, 0.36, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.70, 0.80, 0.92);
uniform vec3 ground_color : source_color = vec3(0.32, 0.33, 0.33);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.85, 0.6);
uniform float sun_disk = 0.9995;
uniform float clouds = 0.5;
uniform float cloud_speed = 0.004;
uniform int quality = 1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= oct) break;
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = max(dot(d, sun_dir), 0.0);
	// rayleigh-ish gradient
	float t = pow(clamp(h, 0.0, 1.0), 0.45);
	vec3 col = mix(horizon_color, zenith_color, t);
	// warm horizon glow towards the sun
	float hz = pow(1.0 - clamp(abs(h), 0.0, 1.0), 6.0);
	col += sun_tint * hz * pow(sd, 3.0) * 0.55;
	// mie halo
	col += sun_tint * (pow(sd, 12.0) * 0.35 + pow(sd, 120.0) * 0.8) * LIGHT0_ENERGY * 0.3;
	// below horizon
	if (h < 0.0) {
		col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	}
	// clouds
	if (h > 0.0 && clouds > 0.01 && quality > 0) {
		vec2 uv = d.xz / (h + 0.08) * 1.6 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		int oct = quality > 1 ? 5 : 4;
		float n = fbm(uv, oct);
		float cov = smoothstep(1.0 - clouds * 0.9, 1.15 - clouds * 0.5, n);
		float dens = fbm(uv * 1.8 + 3.0, 3);
		vec3 cl = mix(vec3(0.62, 0.64, 0.7), vec3(1.0, 0.98, 0.95), dens);
		cl = mix(cl, cl * sun_tint * 1.35, pow(sd, 4.0) * 0.6);
		cl *= mix(0.65, 1.15, LIGHT0_ENERGY * 0.5);
		float fade = smoothstep(0.0, 0.18, h);
		col = mix(col, cl, cov * fade * 0.92);
	}
	// sun disk (not in the radiance cubemap to avoid hard reflections)
	if (!AT_CUBEMAP_PASS) {
		float disk = smoothstep(sun_disk, sun_disk + 0.0002, dot(d, sun_dir));
		col += sun_tint * disk * 18.0 * LIGHT0_ENERGY;
	}
	COLOR = col;
}
