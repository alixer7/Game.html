shader_type spatial;
// Spark-gem collectible used with a MultiMesh: spin + bob are computed per instance on the GPU.

uniform vec4 color : source_color = vec4(1.0, 0.82, 0.25, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.15, 1.0);
uniform float spin_speed = 2.6;
uniform float bob = 0.12;

void vertex() {
	float id = float(INSTANCE_ID);
	float a = TIME * spin_speed + id * 0.61;
	float s = sin(a);
	float c = cos(a);
	VERTEX = vec3(c * VERTEX.x + s * VERTEX.z, VERTEX.y + sin(TIME * 2.0 + id * 0.9) * bob, -s * VERTEX.x + c * VERTEX.z);
	NORMAL = vec3(c * NORMAL.x + s * NORMAL.z, NORMAL.y, -s * NORMAL.x + c * NORMAL.z);
}

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = color.rgb;
	METALLIC = 0.6;
	ROUGHNESS = 0.22;
	EMISSION = glow_color.rgb * (0.85 + f * 1.8);
}
