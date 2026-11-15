shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// الجلد: لون + شفاه + حاجبان/ظل لحية + جوارب + تجويف (AO) مخبوز في ألوان الرؤوس + مسام
// إضاءة مخصّصة: التفاف ناعم مع تشتت دافئ تحت السطح، ولمعان عرق يزداد مع التعب
uniform vec3 skin : source_color = vec3(0.80, 0.60, 0.48);
uniform vec3 lips : source_color = vec3(0.66, 0.36, 0.34);
uniform vec3 hair : source_color = vec3(0.10, 0.07, 0.05);
uniform vec3 sock : source_color = vec3(0.93, 0.93, 0.92);
uniform float stubble = 0.5;
uniform float sweat = 0.0;
uniform sampler2D pores : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mottle : filter_linear_mipmap, repeat_enable;
// خريطة التفاصيل المخبوزة: R شفاه، G حاجبان/رموش، B ظل لحية، A احمرار
uniform sampler2D detail : filter_linear_mipmap;
uniform float flush = 0.0;
varying float cloth;
varying float sweat_mask;

void fragment() {
	vec4 c = COLOR;
	vec4 d = texture(detail, UV);
	float m = texture(mottle, UV * 6.0).r;
	float m2 = texture(mottle, UV * 21.0 + vec2(0.13, 0.57)).r;
	vec3 base = skin * (0.92 + 0.12 * m + 0.05 * m2);
	// تجاويف الجسم أدفأ وأغمق قليلاً
	base = mix(base, base * vec3(1.06, 0.92, 0.88), (1.0 - c.a) * 0.6);
	// احمرار الخدود والأنف والأذنين والمفاصل (يزداد مع الإجهاد)
	float blush = d.a * (0.34 + 0.5 * flush);
	base = mix(base, base * vec3(1.13, 0.84, 0.80), blush);
	float lip = smoothstep(0.25, 0.8, d.r);
	vec3 lipc = mix(lips, lips * 0.78, smoothstep(0.75, 1.0, d.r));
	vec3 col = mix(base, lipc, lip * 0.7);
	float scalp = smoothstep(0.55, 0.95, clamp(c.g, 0.0, 1.0));
	float brow = max(scalp, smoothstep(0.12, 0.8, d.g));
	float stub = (1.0 - brow) * d.b * stubble;
	col = mix(col, mix(col, hair, 0.75) * 0.8, stub * 0.62);
	col = mix(col, hair * 0.9, brow * 0.86);
	col = mix(col, sock, clamp(c.b, 0.0, 1.0));
	cloth = max(c.b, brow);
	// العرق: بقع لامعة تتوزع بنقش ناعم
	sweat_mask = sweat * (1.0 - cloth) * smoothstep(0.3, 0.75, texture(mottle, UV * 3.0 + vec2(0.31, 0.7)).r + 0.25);
	col *= 1.0 - 0.08 * sweat_mask;
	ALBEDO = col;
	AO = pow(clamp(c.a, 0.0, 1.0), 1.5);
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = mix(mix(0.5, 0.85, cloth) - 0.16 * lip + 0.1 * stub, 0.22, sweat_mask);
	SPECULAR = mix(0.4, 0.6, sweat_mask);
	NORMAL_MAP = texture(pores, UV * 38.0).rgb;
	NORMAL_MAP_DEPTH = (0.38 + 0.5 * stub) * (1.0 - c.b);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// التفاف الضوء: الجلد لا ينتقل من المضيء للمظلم بحدة
	float wrap = mix(0.42, 0.15, cloth);
	float diff = max((ndl + wrap) / (1.0 + wrap), 0.0);
	// تشتت تحت السطح: حافة دافئة محمرّة عند حدود الظل
	float sss = smoothstep(-0.4, 0.15, ndl) * (1.0 - smoothstep(0.15, 0.7, ndl)) * (1.0 - cloth);
	DIFFUSE_LIGHT += (diff + vec3(0.55, 0.12, 0.06) * sss * 0.45) * ATTENUATION * LIGHT_COLOR / PI;
	// لمعان: فصّ عريض للجلد الجاف + فصّ حاد للعرق
	vec3 H = normalize(VIEW + LIGHT);
	float nh = max(dot(NORMAL, H), 0.0);
	float nd = max(ndl, 0.0);
	float spec = pow(nh, 22.0) * 0.05 * (1.0 - cloth) + pow(nh, 120.0) * 0.9 * sweat_mask;
	SPECULAR_LIGHT += spec * nd * ATTENUATION * LIGHT_COLOR;
}
