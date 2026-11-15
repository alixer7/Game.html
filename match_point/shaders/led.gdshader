shader_type spatial;
render_mode unshaded;
// شريط LED إعلاني متحرك على واجهة المدرجات
uniform float speed = 0.35;
uniform float brightness = 0.9;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }
void fragment() {
	float u = (abs(wn.x) > 0.5 ? wp.z * sign(wn.x) : -wp.x * sign(wn.z)) + TIME * speed;
	float v = fract(wp.y / 0.7);
	float seg = floor(u / 7.0);
	float su = fract(u / 7.0);
	vec3 bg = mix(vec3(0.02, 0.07, 0.22), vec3(0.03, 0.20, 0.14), step(0.5, hash(seg)));
	bg = mix(bg, vec3(0.20, 0.03, 0.05), step(0.82, hash(seg + 3.7)));
	// حروف مبسّطة: أعمدة مضيئة بعرض عشوائي داخل النطاق الأوسط
	float cu = su * 26.0;
	float ci = floor(cu);
	float on = step(0.38, hash(ci + seg * 13.0)) * step(4.0, ci) * step(ci, 21.0);
	float glyph = on * step(0.12, fract(cu)) * step(0.28, v) * step(v, 0.72);
	glyph *= step(0.2, hash(ci * 3.1 + floor(v * 3.0) + seg));
	vec3 col = mix(bg, vec3(0.95, 0.96, 0.9), glyph);
	col = mix(col, vec3(0.84, 0.93, 0.22), step(su, 0.10) * step(0.2, v) * step(v, 0.8));
	// نقاط الـLED
	vec2 px = fract(vec2(u, wp.y) * 22.0) - 0.5;
	col *= 0.78 + 0.22 * (1.0 - smoothstep(0.2, 0.5, length(px)));
	ALBEDO = col * brightness;
}
