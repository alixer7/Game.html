shader_type spatial;
// أرضية الملعب (v0.5): خطوط بمقاسات ITF مرسومة رياضياً (حادة من أي مسافة) + مواد واقعية لكل أرضية:
//  0 صلبة: أكريليك برمل دقيق، آثار المِمسحة (squeegee)، مناطق مصقولة بالاهتراء، آثار احتكاك الأحذية، لمعان خفيف
//  1 ترابية: غبار طوب بحبيبات، آثار المكنسة والشبكة، خدوش وانزلاقات قرب خط القاعدة، أشرطة خطوط مغبرة مرتفعة قليلاً
//  2 عشبية: خطوط جزّ يتغير لمعانها مع زاوية النظر، نصال عشب، اهتراء بني عند خط القاعدة ومنطقة الإرسال
// + آثار الكرة وآثار انزلاق اللاعبين (على التراب) وظل الشبكة.

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
uniform vec4 slides[16];          // آثار الانزلاق: xy بداية، zw نهاية
uniform int slide_count = 0;

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

// مسافة الحافة (سالبة داخل المستطيل) — لظل أشرطة التراب
float rect_d(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return max(d.x, d.y);
}

float net_h(float x) {
	float t = clamp(abs(x) / 6.40, 0.0, 1.0);
	return 0.914 + 0.156 * t * t;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = wp.xz;
	vec2 a = abs(p);
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.8 + 0.0015;
	float fw = max(fwidth(p.x), fwidth(p.y));
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 vdir = normalize(cam - wp);

	// ---- الخطوط (حافة الطلاء تتموج قليلاً كما في الطلاء الحقيقي) ----
	float edge_n = (texture(grain_tex, p * 9.0).r - 0.5) * 0.004;
	float aal = aa + 0.0008;
	float ln = 0.0;
	ln = max(ln, rect(a, vec2(0.0, HL - 0.05), vec2(DW, 0.05 + edge_n), aal));          // خط القاعدة (10 سم)
	ln = max(ln, rect(a, vec2(DW - 0.025, 0.0), vec2(0.025 + edge_n, HL), aal));        // خط الزوجي
	ln = max(ln, rect(a, vec2(SW - 0.025, 0.0), vec2(0.025 + edge_n, HL), aal));        // خط الفردي
	ln = max(ln, rect(a, vec2(0.0, SL), vec2(SW, 0.025 + edge_n), aal));                // خط الإرسال
	ln = max(ln, rect(a, vec2(0.0, 0.0), vec2(0.025 + edge_n, SL), aal));               // خط المنتصف
	ln = max(ln, rect(a, vec2(0.0, HL - 0.15), vec2(0.025, 0.05), aal));               // علامة المنتصف

	float inside = rect(a, vec2(0.0), vec2(DW, HL), aa);

	// ---- الملمس ----
	float n_lo = texture(noise_tex, p * 0.035).r;
	float n_mid = texture(noise_tex, p * 0.21 + vec2(0.37, 0.11)).r;
	float n_hi = texture(grain_tex, p * 1.9).r;
	float n_fine = texture(grain_tex, p * 7.0 + vec2(0.5)).r;
	float n_xf = texture(grain_tex, p * 23.0 + vec2(0.21, 0.77)).r;
	float far_fade = 1.0 - smoothstep(0.01, 0.06, fw);     // تفاصيل دقيقة تتلاشى بعيداً (بلا وميض)

	vec3 col;
	float rough;
	float spec = 0.5;
	float nrm_k = 0.45;
	if (surface == 0) {
		col = mix(outer_color, court_color, inside);
		// تفاوت لوني واسع (طبقات إعادة الطلاء) + آثار الممسحة الطولية الخافتة
		col *= 0.91 + 0.13 * n_lo + 0.05 * (n_mid - 0.5);
		float squeegee = texture(noise_tex, vec2(p.x * 0.06, p.y * 1.4) + vec2(0.3, 0.9)).r;
		col *= 0.975 + 0.05 * squeegee;
		// رمل الأكريليك: حبيبات فاتحة وداكنة دقيقة
		col *= 0.955 + 0.09 * n_hi;
		col *= mix(1.0, 0.94 + 0.12 * n_xf, far_fade);
		// اهتراء مصقول (أفتح وأنعم) خلف منتصف خط القاعدة وقرب حرف T للإرسال
		float wear = smoothstep(2.6, 0.0, abs(a.y - HL - 0.4)) * smoothstep(3.6, 0.5, a.x) * (0.4 + 0.6 * n_mid);
		wear = max(wear, smoothstep(1.2, 0.0, length(vec2(a.x, a.y - SL))) * 0.45 * n_mid);
		col = mix(col, col * 1.12 + 0.015, wear * 0.45);
		// آثار احتكاك نعال الأحذية: خطوط قصيرة داكنة بزوايا مختلفة قرب خط القاعدة
		vec2 q1 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
		vec2 q2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p;
		float sk = max(smoothstep(0.70, 0.84, texture(noise_tex, q1 * vec2(5.5, 0.9) + vec2(0.2, 0.6)).r),
			smoothstep(0.72, 0.86, texture(noise_tex, q2 * vec2(5.0, 0.8) + vec2(0.7, 0.1)).r));
		float scuff = sk * smoothstep(2.6, 0.2, abs(a.y - HL - 0.2)) * smoothstep(4.6, 1.0, a.x);
		col *= 1.0 - 0.08 * scuff;
		rough = 0.56 + 0.20 * n_hi - 0.14 * wear + 0.05 * scuff;
		spec = 0.5;
		nrm_k = 0.5;
	} else if (surface == 1) {
		vec3 clay = vec3(0.70, 0.33, 0.17);
		vec3 clay_dark = vec3(0.55, 0.24, 0.12);
		vec3 clay_dust = vec3(0.80, 0.47, 0.30);
		float damp = smoothstep(0.35, 0.7, n_lo);
		col = mix(clay, clay_dark, damp * 0.55);
		col = mix(col, clay_dust, smoothstep(0.55, 0.9, n_mid) * 0.35);
		// آثار المكنسة/الشبكة: خطوط طولية متموجة + قوس الجرّ عند الأطراف
		float sweep = sin(p.x * 24.0 + n_mid * 9.0 + sin(p.y * 0.35) * 2.0) * 0.5 + 0.5;
		float sweep2 = sin(p.x * 61.0 + n_hi * 6.0) * 0.5 + 0.5;
		col *= 0.95 + 0.05 * sweep + 0.025 * sweep2 * far_fade;
		// حبيبات الطوب المسحوق
		col *= 0.90 + 0.20 * n_hi * n_fine * 2.0;
		col *= mix(1.0, 0.92 + 0.16 * n_xf, far_fade);
		// منطقة الحركة قرب خط القاعدة: تراب مزاح فاتح + خدوش جانبية داكنة
		float zone = smoothstep(2.4, 0.0, abs(a.y - HL - 0.3)) * smoothstep(5.0, 1.0, a.x);
		col = mix(col, clay_dust, zone * n_mid * 0.4);
		float scr = smoothstep(0.62, 0.80, texture(noise_tex, vec2(p.x * 0.9, p.y * 6.5) + vec2(0.4, 0.2)).r) * zone;
		col = mix(col, clay_dark * 0.92, scr * 0.45);
		rough = 0.96;
		spec = 0.2;
		nrm_k = 0.95;
	} else {
		vec3 g1 = vec3(0.150, 0.300, 0.095);
		vec3 g2 = vec3(0.185, 0.355, 0.115);
		// خطوط الجزّ: النصال في كل شريط منحنية باتجاه معاكس، فيتبدّل اللمعان مع زاوية النظر
		float sid = floor(p.x / 0.915 + 0.5);
		float dirs = mod(sid, 2.0) * 2.0 - 1.0;
		float sheen = 0.5 + 0.5 * dirs * clamp(vdir.z * 1.6, -1.0, 1.0);
		col = mix(g1, g2, sheen);
		col *= 0.86 + 0.28 * n_fine;
		col *= 0.93 + 0.12 * n_lo;
		col *= mix(1.0, 0.85 + 0.30 * n_xf, far_fade);
		// اهتراء العشب عند خط القاعدة ومنطقة الإرسال
		float wear = smoothstep(1.9, 0.0, abs(a.y - HL + 0.2)) * smoothstep(3.4, 0.6, a.x);
		wear = max(wear, smoothstep(1.3, 0.0, abs(a.y - SL)) * smoothstep(2.2, 0.3, a.x) * 0.5);
		wear *= 0.35 + 0.75 * n_mid;
		vec3 dirt = mix(vec3(0.50, 0.42, 0.24), vec3(0.42, 0.33, 0.19), n_hi);
		col = mix(col, dirt, clamp(wear, 0.0, 1.0) * 0.8);
		rough = 0.93 - 0.08 * sheen;
		spec = 0.25;
		nrm_k = 0.8;
	}

	// ---- آثار الكرة (واضحة على التراب، خافتة على غيره) ----
	for (int i = 0; i < mark_count; i++) {
		vec2 d = p - marks[i].xy;
		float m = 1.0 - smoothstep(marks[i].z * 0.55, marks[i].z, length(d * vec2(1.0, 0.72)));
		if (surface == 1) {
			col = mix(col, vec3(0.50, 0.21, 0.10), m * 0.75 * marks[i].w);
		} else if (surface == 0) {
			col = mix(col, col * 0.88 + vec3(0.012, 0.015, 0.0), m * 0.35 * marks[i].w);
		} else {
			col = mix(col, col * 0.86, m * 0.35 * marks[i].w);
		}
	}
	// ---- آثار انزلاق اللاعبين على التراب: شريط داكن مزاح مع حافة فاتحة من التراب المتراكم ----
	for (int i = 0; i < slide_count; i++) {
		float ds = seg_dist(p, slides[i].xy, slides[i].zw);
		float core = 1.0 - smoothstep(0.05, 0.11, ds);
		float rim = smoothstep(0.08, 0.12, ds) * (1.0 - smoothstep(0.12, 0.19, ds));
		col = mix(col, vec3(0.47, 0.20, 0.10), core * 0.6);
		col = mix(col, vec3(0.84, 0.52, 0.34), rim * 0.35);
	}

	// ---- الخطوط فوق الملمس ----
	vec3 lc = line_color;
	if (surface == 1) {
		// أشرطة بيضاء يغطيها غبار التراب جزئياً
		lc = mix(line_color, vec3(0.86, 0.62, 0.48), 0.20 + 0.30 * n_hi * (0.6 + 0.8 * n_mid));
	} else if (surface == 2) {
		lc = mix(line_color, vec3(0.6, 0.72, 0.45), 0.10 + 0.25 * n_fine);
	} else {
		lc *= 0.95 + 0.07 * n_hi;
	}
	col = mix(col, lc, ln);
	rough = mix(rough, surface == 0 ? 0.42 : 0.6, ln * 0.7);
	if (surface == 1) {
		// الأشرطة مرتفعة ~2 مم: ظل دقيق على الجهة البعيدة عن الشمس
		float dl = min(min(rect_d(a, vec2(0.0, HL - 0.05), vec2(DW, 0.05)), rect_d(a, vec2(SW - 0.025, 0.0), vec2(0.025, HL))),
			min(rect_d(a, vec2(0.0, SL), vec2(SW, 0.025)), rect_d(a, vec2(0.0, 0.0), vec2(0.025, SL))));
		float sh = smoothstep(0.0, 0.004, dl) * (1.0 - smoothstep(0.004, 0.014, dl));
		col *= 1.0 - 0.18 * sh * far_fade;
	}

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
	col *= mix(0.62, 1.0, smoothstep(0.0, 1.6, edge));

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = spec;
	// حبيبات السطح: خشونة دقيقة تلتقط ضوء الشمس (رمل الأكريليك / حبيبات التراب / نصل العشب)
	NORMAL_MAP = texture(grain_nrm, p * (surface == 2 ? 2.4 : 3.6)).rgb;
	NORMAL_MAP_DEPTH = nrm_k * (1.0 - 0.6 * ln) * (1.0 - smoothstep(0.012, 0.05, fw));
}
