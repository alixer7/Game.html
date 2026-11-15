shader_type spatial;
// أرضية الملعب: خطوط بمقاسات ITF مرسومة رياضياً (حادة من أي مسافة) + ملمس حسب نوع الأرضية
// 0 صلبة (أكريليك) ، 1 ترابية ، 2 عشبية

uniform int surface = 0;
uniform vec3 court_color : source_color = vec3(0.10, 0.28, 0.55);
uniform vec3 outer_color : source_color = vec3(0.13, 0.36, 0.30);
uniform vec3 line_color : source_color = vec3(0.94, 0.94, 0.92);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_nrm : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec2 arena_half = vec2(10.5, 19.5);
uniform vec3 sun_dir = vec3(0.38, 0.82, 0.42);
uniform vec4 marks[24];
uniform int mark_count = 0;

varying vec3 wp;

const float HL = 11.885;
const float SW = 4.115;
const float DW = 5.485;
const float SL = 6.40;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float rect(vec2 p, vec2 c, vec2 h, float aa) {
	vec2 d = abs(p - c) - h;
	return 1.0 - smoothstep(-aa, aa, max(d.x, d.y));
}

float net_h(float x) {
	float t = clamp(abs(x) / 6.40, 0.0, 1.0);
	return 0.914 + 0.156 * t * t;
}

void fragment() {
	vec2 p = wp.xz;
	vec2 a = abs(p);
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.8 + 0.0015;

	// ---- الخطوط ----
	float ln = 0.0;
	ln = max(ln, rect(a, vec2(0.0, HL - 0.05), vec2(DW, 0.05), aa));            // خط القاعدة (10 سم)
	ln = max(ln, rect(a, vec2(DW - 0.025, 0.0), vec2(0.025, HL), aa));          // خط الزوجي
	ln = max(ln, rect(a, vec2(SW - 0.025, 0.0), vec2(0.025, HL), aa));          // خط الفردي
	ln = max(ln, rect(a, vec2(0.0, SL), vec2(SW, 0.025), aa));                  // خط الإرسال
	ln = max(ln, rect(a, vec2(0.0, 0.0), vec2(0.025, SL), aa));                 // خط المنتصف
	ln = max(ln, rect(a, vec2(0.0, HL - 0.15), vec2(0.025, 0.05), aa));         // علامة المنتصف

	float inside = rect(a, vec2(0.0), vec2(DW, HL), aa);

	// ---- الملمس ----
	float n_lo = texture(noise_tex, p * 0.035).r;
	float n_mid = texture(noise_tex, p * 0.21 + vec2(0.37, 0.11)).r;
	float n_hi = texture(grain_tex, p * 1.9).r;
	float n_fine = texture(grain_tex, p * 7.0 + vec2(0.5)).r;

	vec3 col;
	float rough;
	float spec = 0.5;
	if (surface == 0) {
		col = mix(outer_color, court_color, inside);
		// تفاوت لوني خفيف + حبيبات الرمل في الطلاء + اهتراء قرب خط القاعدة
		col *= 0.90 + 0.14 * n_lo + 0.06 * (n_mid - 0.5);
		col *= 0.955 + 0.09 * n_hi;
		float wear = smoothstep(2.6, 0.0, abs(a.y - HL - 0.4)) * smoothstep(3.6, 0.5, a.x) * (0.4 + 0.6 * n_mid);
		col = mix(col, col * 1.12 + 0.015, wear * 0.45);
		// آثار احتكاك الأحذية الداكنة قرب خط القاعدة + لمسات فرشاة الطلاء العرضية
		float scuff = smoothstep(0.66, 0.80, texture(noise_tex, p * vec2(5.5, 1.1) + vec2(0.2, 0.6)).r) * smoothstep(2.2, 0.2, abs(a.y - HL - 0.1)) * smoothstep(4.2, 1.0, a.x);
		col *= 1.0 - 0.06 * scuff;
		rough = 0.58 + 0.20 * n_hi - 0.12 * wear;
		spec = 0.5;
	} else if (surface == 1) {
		vec3 clay = vec3(0.70, 0.33, 0.17);
		vec3 clay_dark = vec3(0.56, 0.25, 0.13);
		vec3 clay_dust = vec3(0.80, 0.47, 0.30);
		float damp = smoothstep(0.35, 0.7, n_lo);
		col = mix(clay, clay_dark, damp * 0.55);
		col = mix(col, clay_dust, smoothstep(0.55, 0.9, n_mid) * 0.35);
		// آثار المكنسة (خطوط طولية ناعمة) والحبيبات
		float sweep = sin(p.x * 26.0 + n_mid * 9.0) * 0.5 + 0.5;
		col *= 0.95 + 0.05 * sweep;
		col *= 0.90 + 0.20 * n_hi * n_fine * 2.0;
		// منطقة الانزلاق قرب خط القاعدة (تراب مزاح)
		float slide = smoothstep(2.4, 0.0, abs(a.y - HL - 0.3)) * smoothstep(4.5, 1.0, a.x) * n_mid;
		col = mix(col, clay_dust, slide * 0.4);
		rough = 0.96;
		spec = 0.2;
	} else {
		vec3 g1 = vec3(0.150, 0.300, 0.095);
		vec3 g2 = vec3(0.185, 0.355, 0.115);
		float stripe = step(0.5, fract(p.x / 1.83 + 0.25));
		col = mix(g1, g2, stripe);
		col *= 0.86 + 0.28 * n_fine;
		col *= 0.93 + 0.12 * n_lo;
		// اهتراء العشب عند خط القاعدة ومنطقة الإرسال
		float wear = smoothstep(1.9, 0.0, abs(a.y - HL + 0.2)) * smoothstep(3.4, 0.6, a.x);
		wear = max(wear, smoothstep(1.3, 0.0, abs(a.y - SL)) * smoothstep(2.2, 0.3, a.x) * 0.5);
		wear *= 0.35 + 0.75 * n_mid;
		col = mix(col, vec3(0.50, 0.42, 0.24), clamp(wear, 0.0, 1.0) * 0.8);
		rough = 0.93;
		spec = 0.25;
	}

	// ---- آثار الكرة (واضحة على التراب) ----
	for (int i = 0; i < mark_count; i++) {
		vec2 d = p - marks[i].xy;
		float m = 1.0 - smoothstep(marks[i].z * 0.55, marks[i].z, length(d * vec2(1.0, 0.72)));
		if (surface == 1) {
			col = mix(col, vec3(0.50, 0.21, 0.10), m * 0.75 * marks[i].w);
		} else {
			col = mix(col, col * 0.86, m * 0.35 * marks[i].w);
		}
	}

	// ---- الخطوط فوق الملمس ----
	vec3 lc = line_color;
	if (surface == 1) {
		lc = mix(line_color, vec3(0.86, 0.62, 0.48), 0.22 + 0.25 * n_hi);
	} else if (surface == 2) {
		lc = mix(line_color, vec3(0.6, 0.72, 0.45), 0.10 + 0.25 * n_fine);
	} else {
		lc *= 0.94 + 0.08 * n_hi;
	}
	col = mix(col, lc, ln);
	rough = mix(rough, 0.55, ln * 0.6);

	// ---- ظل الشبكة (شبه شفاف) وشريطها ----
	if (sun_dir.z != 0.0) {
		float t = -wp.z / sun_dir.z;
		if (t > 0.0) {
			float hx = wp.x + sun_dir.x * t;
			float hy = sun_dir.y * t;
			float top = net_h(hx);
			float in_x = 1.0 - smoothstep(6.38, 6.44, abs(hx));
			float body = (1.0 - smoothstep(top - 0.03, top + 0.01, hy)) * in_x;
			float tape = (1.0 - smoothstep(0.02, 0.06, abs(hy - top + 0.02))) * in_x;
			float strap = (1.0 - smoothstep(0.03, 0.06, abs(hx))) * step(hy, top);
			col *= 1.0 - 0.17 * body - 0.30 * max(tape, strap);
		}
	}

	// ---- تظليل تماسّ الحواجز المحيطة (إحساس بالعمق عند أطراف الأرضية) ----
	float edge = min(arena_half.x - a.x, arena_half.y - a.y);
	col *= mix(0.66, 1.0, smoothstep(0.0, 1.5, edge));

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = spec;
	// حبيبات السطح: خشونة دقيقة تلتقط ضوء الشمس (رمل الأكريليك / حبيبات التراب / نصل العشب)
	NORMAL_MAP = texture(grain_nrm, p * (surface == 2 ? 2.4 : 3.6)).rgb;
	float fw = max(fwidth(p.x), fwidth(p.y));
	NORMAL_MAP_DEPTH = (surface == 0 ? 0.45 : (surface == 1 ? 0.9 : 0.75)) * (1.0 - 0.6 * ln) * (1.0 - smoothstep(0.012, 0.05, fw));
}
