shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.12, 0.42, 0.42);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.2);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);
uniform float wave_scale = 1.0;
uniform float flow_speed = 0.0;        // >0 for rivers (UV.y along flow)
uniform float clarity = 4.0;           // metres until fully deep coloured
uniform int quality = 1;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 v_world;

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

float waves(vec2 p, float t) {
	float h = 0.0;
	if (flow_speed > 0.0) {
		vec2 q = vec2(p.x, p.y - t * flow_speed);
		h += vnoise(q * vec2(0.6, 0.35)) * 0.5;
		h += vnoise(q * vec2(1.7, 1.0) + 3.1) * 0.3;
		h += vnoise(q * vec2(4.0, 2.6) + 7.7) * 0.15;
		return h;
	}
	h += sin(dot(p, vec2(0.08, 0.05)) + t * 0.9) * 0.35;
	h += sin(dot(p, vec2(-0.05, 0.11)) + t * 1.2) * 0.25;
	h += vnoise(p * 0.18 + vec2(t * 0.15, t * 0.08)) * 0.6;
	h += vnoise(p * 0.55 - vec2(t * 0.25, -t * 0.12)) * 0.3;
	h += vnoise(p * 1.6 + vec2(t * 0.4, t * 0.3)) * 0.12;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = flow_speed > 0.0 ? UV * vec2(1.0, 1.0) : v_world.xz;
	float e = 0.15;
	float h0 = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	vec3 n_world = normalize(vec3((h0 - hx) / e * 0.35 * wave_scale, 1.0, (h0 - hz) / e * 0.35 * wave_scale));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float thickness = 20.0;
	if (quality > 0) {
		float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
		vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene_z = -upos.z / upos.w;
		thickness = max(scene_z + VERTEX.z, 0.0);
	}
	float dfac = clamp(thickness / clarity, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, dfac);
	float foam_n = vnoise(v_world.xz * 0.9 + vec2(t * 0.3, 0.0)) * 0.6 + vnoise(v_world.xz * 3.0 - t * 0.2) * 0.4;
	float shore = 1.0 - smoothstep(0.0, 1.4, thickness);
	float foam = clamp(shore * smoothstep(0.35, 0.75, foam_n + shore * 0.4), 0.0, 1.0);
	if (flow_speed > 0.0) {
		foam += smoothstep(0.78, 0.95, h0) * 0.35;
	}
	foam = clamp(foam, 0.0, 1.0);
	col = mix(col, foam_color, foam);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.6, foam);
	SPECULAR = 0.55;
	METALLIC = 0.0;
	ALPHA = clamp(mix(0.55, 0.97, dfac) + foam, 0.0, 1.0);
}
