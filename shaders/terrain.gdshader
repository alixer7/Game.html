shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// تضاريس: لون الرؤوس من مولّد البيئات + تفاصيل متعددة المقاييس + صخر على المنحدرات + ثلج ورطوبة ديناميكية
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wetness = 0.0;
uniform float snow = 0.0;
uniform vec2 hole_center = vec2(0.0);
uniform float hole_radius = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

void fragment() {
	if (hole_radius > 0.0 && distance(wpos.xz, hole_center) < hole_radius) {
		discard;
	}
	float n1 = texture(detail_tex, wpos.xz * 0.012).r;
	float n2 = texture(detail_tex, wpos.xz * 0.085).r;
	float n3 = texture(detail_tex, wpos.xz * 0.53).r;
	vec3 base = COLOR.rgb;
	vec3 col = base * (0.6 + n1 * 0.32 + n2 * 0.3 + n3 * 0.2);
	float slope = 1.0 - wnrm.y;
	float rk = smoothstep(0.2, 0.4, slope + (n2 - 0.5) * 0.22);
	vec3 rock = vec3(0.41, 0.39, 0.36) * (0.62 + n2 * 0.5 + n3 * 0.28);
	col = mix(col, rock, rk);
	float sn = clamp(snow * (COLOR.a * 1.6 + 0.15), 0.0, 1.0) * (1.0 - rk * 0.8);
	col = mix(col, vec3(0.8, 0.82, 0.86) * (0.92 + n3 * 0.1), sn);
	col *= 1.0 - wetness * 0.3 * (1.0 - sn);
	ALBEDO = col;
	ROUGHNESS = clamp(mix(0.95, 0.42, wetness) - rk * 0.05, 0.05, 1.0);
	SPECULAR = 0.22 + wetness * 0.3;
	NORMAL_MAP = texture(normal_tex, wpos.xz * 0.32).rgb;
	NORMAL_MAP_DEPTH = 0.45 + rk * 0.8;
}
