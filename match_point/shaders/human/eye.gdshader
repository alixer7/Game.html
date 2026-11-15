shader_type spatial;
// العين: صلبة + قزحية بنقوش شعاعية + بؤبؤ + لمعان رطب
uniform vec3 iris_color : source_color = vec3(0.30, 0.20, 0.12);
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float f = COLOR.r * 2.0 - 1.0;      // جيب تمام الزاوية عن الأمام
	float ang = acos(clamp(f, -1.0, 1.0));
	float iris = 1.0 - smoothstep(0.46, 0.52, ang);
	float pupil = 1.0 - smoothstep(0.15, 0.18, ang);
	float ring = smoothstep(0.36, 0.5, ang) * iris;
	float rays = 0.8 + 0.2 * sin(atan(lp.y, lp.x) * 40.0);
	vec3 sclera = mix(vec3(0.97, 0.95, 0.93), vec3(0.88, 0.70, 0.68), smoothstep(1.3, 1.8, ang));
	vec3 col = mix(sclera, iris_color * rays * (1.0 - 0.45 * ring), iris);
	col = mix(col, vec3(0.02), pupil);
	ALBEDO = col;
	// العين غائرة تحت الجفن فتُظلَّل كلياً؛ إنارة ذاتية خفيفة تحفظ بياضها ولون القزحية
	EMISSION = col * 0.5;
	ROUGHNESS = 0.22;
	SPECULAR = 0.35;
}
