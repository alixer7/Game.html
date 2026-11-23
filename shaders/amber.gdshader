shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// All amber pickups in one MultiMesh: spin + bob in the vertex shader (no
// per-pickup script work), glowing amber.

uniform vec3 glow : source_color = vec3(1.0, 0.55, 0.1);

void vertex() {
	float ph = float(INSTANCE_ID) * 1.7;
	float a = TIME * 2.5 + ph;
	float c = cos(a);
	float s = sin(a);
	VERTEX = vec3(c * VERTEX.x + s * VERTEX.z, VERTEX.y + 0.9 + sin(TIME * 3.0 + ph) * 0.08, -s * VERTEX.x + c * VERTEX.z);
	NORMAL = vec3(c * NORMAL.x + s * NORMAL.z, NORMAL.y, -s * NORMAL.x + c * NORMAL.z);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.15;
	EMISSION = glow * 1.4;
}
