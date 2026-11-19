shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// UV.x: 0..1 across the road (left -> right), UV.y: metres along the road
uniform sampler2DArray surf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer = 0.0;     // 0 asphalt, 1 cobble, 2 gravel, 3 concrete
uniform float width = 10.0;
uniform int style = 0;         // 0 highway 1 avenue 2 street 3 country 4 mountain 5 track 6 none
uniform float tile = 0.22;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wear = 1.0;

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

// anti-aliased line of half-width hw centred at c
float line(float x, float c, float hw) {
	float d = abs(x - c);
	float aa = fwidth(x) * 1.2 + 0.002;
	return 1.0 - smoothstep(hw - aa, hw + aa, d);
}

float dash(float y, float on, float period) {
	float f = mod(y, period);
	float aa = fwidth(y) + 0.01;
	return smoothstep(0.0, aa, f) * (1.0 - smoothstep(on - aa, on, f));
}

void vertex() {
	vec3 ref = abs(NORMAL.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
	TANGENT = normalize(cross(ref, NORMAL));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	float x = (UV.x - 0.5) * width;
	float y = UV.y;
	float ax = abs(x);
	vec2 tuv = vec2(x, y) * tile;
	vec4 alb = texture(surf_albedo, vec3(tuv, layer));
	vec3 nrm = texture(surf_normal, vec3(tuv, layer)).rgb;
	vec4 alb2 = texture(surf_albedo, vec3(tuv * 0.27 + 0.31, layer));
	alb = mix(alb, alb2, 0.35);
	vec3 col = alb.rgb * tint;
	float rough = alb.a;
	float n1 = vnoise(vec2(x * 0.5, y * 0.08));
	float n2 = vnoise(vec2(x * 2.0, y * 0.6));
	// patches / repairs / tyre-polished wheel tracks
	if (layer < 0.5) {
		col *= mix(0.85, 1.12, vnoise(vec2(x * 0.15, y * 0.03)));
		float lane_w = 3.6;
		float lx = mod(ax, lane_w) / lane_w;
		float tracks = (exp(-pow((lx - 0.27) * 9.0, 2.0)) + exp(-pow((lx - 0.73) * 9.0, 2.0))) * wear;
		col *= 1.0 - tracks * 0.12;
		rough -= tracks * 0.1;
	}
	// edge grime
	float edge = smoothstep(width * 0.5 - 1.2, width * 0.5, ax);
	col = mix(col, col * vec3(0.78, 0.72, 0.64), edge * 0.6 * (0.6 + 0.4 * n1));

	float m = 0.0;
	vec3 mc = vec3(0.92, 0.92, 0.88);
	vec3 yellow = vec3(0.95, 0.72, 0.12);
	float myellow = 0.0;
	if (style == 0) {
		myellow = line(ax, 1.65, 0.07);
		m += line(ax, 5.25, 0.075) * dash(y, 4.0, 12.0);
		m += line(ax, 8.6, 0.1);
	} else if (style == 1) {
		myellow = line(ax, 0.18, 0.06);
		m += line(ax, 3.7, 0.07) * dash(y, 3.0, 9.0);
		m += line(ax, width * 0.5 - 1.6, 0.08);
	} else if (style == 2) {
		m += line(x, 0.0, 0.07) * dash(y, 3.0, 9.0);
		m += line(ax, width * 0.5 - 1.0, 0.07);
	} else if (style == 3) {
		myellow = line(x, 0.0, 0.07) * dash(y, 4.0, 10.0);
		m += line(ax, width * 0.5 - 0.45, 0.07);
	} else if (style == 4) {
		myellow = line(ax, 0.16, 0.06);
		m += line(ax, width * 0.5 - 0.4, 0.07);
	} else if (style == 5) {
		// kerbs: red / white blocks on the outer metre
		float kerb = smoothstep(width * 0.5 - 1.25, width * 0.5 - 1.2, ax);
		float stripe = step(0.5, fract(y / 4.0));
		col = mix(col, mix(vec3(0.75, 0.06, 0.04), vec3(0.92, 0.92, 0.9), stripe), kerb);
		rough = mix(rough, 0.6, kerb);
		m += line(ax, width * 0.5 - 1.35, 0.08);
	}
	float worn = smoothstep(0.15, 0.55, n2 * 0.7 + n1 * 0.3) * wear;
	m *= 1.0 - worn * 0.45;
	myellow *= 1.0 - worn * 0.4;
	col = mix(col, mc, clamp(m, 0.0, 1.0));
	col = mix(col, yellow, clamp(myellow, 0.0, 1.0));
	rough = mix(rough, 0.55, clamp(m + myellow, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.25, 1.0);
	SPECULAR = 0.4;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 0.8 * (1.0 - clamp(m + myellow, 0.0, 1.0));
}
