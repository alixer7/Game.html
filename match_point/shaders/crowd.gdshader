shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// الجمهور (منخفض الدقة عمداً للأداء): شكل بشري مبسَّط من نفس النموذج التشريحي
// COLOR.r من النموذج: 0 بشرة، 1/3 قميص، 2/3 بنطال، 1 شعر — لون القميص من لون النسخة
uniform float excitement = 0.0;
varying vec3 shirt;
varying float skin_t;
varying float hair_t;
varying float region;

void vertex() {
	shirt = INSTANCE_CUSTOM.rgb;
	region = UV.x;
	float a = INSTANCE_CUSTOM.a * 10.0;
	skin_t = floor(a + 0.001) / 9.0;
	hair_t = clamp(fract(a + 0.001) / 0.9, 0.0, 1.0);
	float ph = float(INSTANCE_ID) * 1.713;
	float idle = sin(TIME * 0.7 + ph) * 0.006;
	float cheer = max(0.0, sin(TIME * (6.0 + fract(ph) * 3.0) + ph)) * 0.10 * excitement;
	VERTEX.y += idle + cheer * smoothstep(0.3, 0.9, VERTEX.y);
}

void fragment() {
	vec3 skin = mix(vec3(0.36, 0.22, 0.15), vec3(0.88, 0.68, 0.55), skin_t);
	vec3 hair = mix(vec3(0.05, 0.04, 0.03), vec3(0.45, 0.32, 0.18), hair_t * hair_t);
	vec3 c = skin;
	if (region > 0.83) { c = hair; }
	else if (region > 0.5) { c = vec3(0.12, 0.13, 0.18) + 0.15 * vec3(hair_t, skin_t * 0.5, 0.3); }
	else if (region > 0.17) { c = shirt; }
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
