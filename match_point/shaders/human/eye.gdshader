shader_type spatial;
render_mode specular_schlick_ggx;
// العين: UV يحمل اتجاه كرة العين في وضع الراحة (x, y)، فالمسافة عن المركز = جيب الزاوية عن محور النظر.
// صلبة بأوعية خفيفة وظل عند الأطراف + قزحية بألياف شعاعية وحلقة داكنة (limbal ring) + بؤبؤ + لمعان رطب.
uniform vec3 iris_color : source_color = vec3(0.30, 0.20, 0.12);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float ang = atan(d.y, d.x);
	float iris = 1.0 - smoothstep(0.43, 0.48, r);
	float pupil = 1.0 - smoothstep(0.145, 0.175, r);
	float limbal = smoothstep(0.34, 0.47, r) * iris;
	// ألياف القزحية: خطوط شعاعية متعرجة مع بقع
	float fib = 0.72 + 0.18 * sin(ang * 52.0 + 2.2 * sin(ang * 9.0 + r * 20.0)) + 0.10 * sin(ang * 23.0 - r * 30.0);
	fib *= 0.9 + 0.2 * hash(floor(vec2(ang * 18.0, r * 26.0)));
	vec3 icol = iris_color * fib * mix(1.3, 0.45, limbal);
	// الطوق الفاتح حول البؤبؤ
	icol = mix(icol, iris_color * 1.7 + vec3(0.04, 0.03, 0.01), (1.0 - smoothstep(0.17, 0.27, r)) * 0.4);
	// الصلبة: بياض دافئ يميل للاحمرار نحو الزوايا مع شعيرات دقيقة
	float vein = smoothstep(0.92, 1.0, sin(ang * 13.0 + sin(r * 18.0) * 2.0)) * smoothstep(0.55, 0.95, r);
	vec3 sclera = mix(vec3(0.93, 0.91, 0.88), vec3(0.86, 0.70, 0.66), smoothstep(0.62, 1.0, r));
	sclera = mix(sclera, vec3(0.75, 0.32, 0.30), vein * 0.25);
	vec3 col = mix(sclera, icol, iris);
	col = mix(col, vec3(0.012), pupil);
	ALBEDO = col;
	// العين غائرة تحت الجفن فتُظلَّل كثيراً؛ إنارة ذاتية خفيفة تحفظ القزحية والبياض
	EMISSION = col * 0.32;
	ROUGHNESS = 0.06;
	SPECULAR = 0.75;
}
