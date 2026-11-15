shader_type spatial;
render_mode diffuse_burley;
// المدرجات والهياكل: المقاعد والممرات والسلالم تُرسم رياضياً فوق خرسانة مدرّجة (بلا مضلعات إضافية).
// نوع السطح في ألفا لون الرأس: 1 خرسانة مدرّجة بمقاعد، 0.75 باطن السقف، 0.5 واجهة زجاجية، 0.25 حاجز شبكي/درابزين، 0 لون سادة
uniform vec3 seat_a : source_color = vec3(0.07, 0.15, 0.36);
uniform vec3 seat_b : source_color = vec3(0.10, 0.22, 0.48);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float x_in = 10.75;
uniform float z_in = 19.75;
uniform float base_h = 1.30;
uniform float row_h = 0.44;
uniform float row_d = 0.85;
uniform float u0_end = -24.05;
uniform float u0_side = -19.45;
uniform float shift_end = 5.0;
uniform float shift_side = 14.0;
varying vec3 wp;
varying vec3 wn;
varying float kind;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	kind = COLOR.a;
}

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void fragment() {
	vec3 col = COLOR.rgb;
	float rough = 0.86;
	float spec = 0.35;
	float n = texture(noise_tex, wp.xz * 0.09 + wp.y * 0.13).r;
	float n2 = texture(noise_tex, wp.xz * 0.7 + wp.yy * 0.9).r;
	if (kind > 0.9) {
		bool end_stand = abs(wp.z) > z_in;
		float u = end_stand ? wp.x : wp.z;
		float d = end_stand ? abs(wp.z) - z_in : abs(wp.x) - x_in;
		float su = (u - (end_stand ? u0_end : u0_side)) / 0.56 + 0.5;
		float si = floor(su);
		float sf = fract(su);
		float am = mod(si + (end_stand ? shift_end : shift_side), 16.0);
		bool aisle = am < 1.5;
		float ry = (wp.y - (base_h - row_h)) / row_h;
		float row = floor(ry + 0.001);
		vec3 conc = col * (0.86 + 0.22 * n) * (0.94 + 0.10 * n2);
		col = conc;
		if (wp.y > base_h - row_h - 0.02) {
			vec3 seat = (row < 6.0 ? seat_a : seat_b) * (0.86 + 0.26 * hash(si * 7.31 + row * 3.17));
			float gap = smoothstep(0.03, 0.07, sf) * (1.0 - smoothstep(0.93, 0.97, sf));
			if (wn.y > 0.5) {
				// سطح الدرجة: وسادة المقعد + ممشى خرساني
				float df = fract(d / row_d);
				if (aisle) {
					col = conc * 1.12;
					col = mix(col, vec3(0.86, 0.72, 0.16), 1.0 - smoothstep(0.03, 0.06, df));       // حافة السلم الصفراء
				} else {
					float pan = smoothstep(0.30, 0.34, df) * (1.0 - smoothstep(0.80, 0.84, df)) * gap;
					col = mix(conc, seat * 0.9, pan);
					rough = mix(rough, 0.5, pan);
				}
			} else if (abs(wn.y) < 0.3) {
				// واجهة الدرجة: ظهر المقعد
				float fy = fract(ry);
				if (aisle) {
					col = conc * (fy > 0.5 ? 0.92 : 0.78);
				} else {
					float back = smoothstep(0.10, 0.16, fy) * (1.0 - smoothstep(0.95, 1.0, fy)) * gap;
					vec3 sc = seat * (0.78 + 0.34 * fy);
					col = mix(conc * 0.62, sc, back);
					rough = mix(rough, 0.42, back);
					spec = mix(spec, 0.5, back);
				}
			}
		}
	} else if (kind > 0.6) {
		// باطن السقف: ألواح معدنية وعوارض
		float along = abs(wn.y) > 0.5 ? wp.z : wp.y;
		float beams = 1.0 - smoothstep(0.02, 0.05, abs(fract(along / 3.2) - 0.5) * 2.0 - 0.9 + 0.9);
		float panels = smoothstep(0.0, 0.04, abs(fract(wp.x / 1.2) - 0.5) - 0.46) ;
		col *= 0.90 + 0.10 * n;
		col *= 1.0 - 0.22 * panels;
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.03, 0.06, abs(fract(along / 3.2) - 0.5)));
		rough = 0.55;
	} else if (kind > 0.35) {
		// واجهة المقصورات الزجاجية: عوارض رأسية وانعكاس السماء
		bool xface = abs(wn.x) > 0.5;
		float u = xface ? wp.z : wp.x;
		float mull = 1.0 - smoothstep(0.03, 0.05, abs(fract(u / 2.4) - 0.5) * 2.4);
		float fy = fract(wp.y * 0.5);
		vec3 glass = mix(vec3(0.05, 0.08, 0.12), vec3(0.42, 0.56, 0.72), smoothstep(-0.2, 1.0, fy) * 0.55 + 0.12 * n);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		glass = mix(glass, vec3(0.62, 0.74, 0.88), fres * 0.6);
		col = mix(glass, vec3(0.82, 0.84, 0.86), mull);
		rough = mix(0.12, 0.6, mull);
		spec = 0.7;
	} else if (kind > 0.1) {
		// خرسانة/دهان بملمس خفيف
		col *= 0.90 + 0.16 * n;
		rough = 0.8;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
