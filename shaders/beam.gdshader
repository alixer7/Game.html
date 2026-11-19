shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.6, 0.1);

void fragment() {
	// UV.y: 0 top .. 1 bottom on CylinderMesh
	float h = UV.y;
	float fade = pow(h, 2.2);
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0 + h * 12.0);
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = color * fade * pulse * (0.35 + rim * 0.9) * 1.6;
}
