shader_type spatial;
// كرة التنس: لباد أصفر مخضر مع الدرز الأبيض المنحني
varying vec3 lp;

void vertex() {
	lp = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(lp);
	// الدرز: تقاطع الكرة مع سطح سرجي z = k·2xy
	float g = n.z * (1.0 - n.z * n.z) - 0.56 * 2.0 * n.x * n.y;
	float seam = 1.0 - smoothstep(0.035, 0.085, abs(g));
	vec3 felt = vec3(0.80, 0.92, 0.16);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = mix(felt, vec3(0.96, 0.97, 0.92), seam) + fres * 0.10;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	EMISSION = felt * 0.07;
}
