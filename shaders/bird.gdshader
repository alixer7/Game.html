shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float flap_speed = 9.0;

void vertex() {
	float wing = COLOR.a;
	float ph = dot(MODEL_MATRIX[3].xyz, vec3(0.37, 0.11, 0.23));
	float f = sin(TIME * flap_speed + ph) * 0.9 + 0.2;
	VERTEX.y += abs(VERTEX.x) * f * wing;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
