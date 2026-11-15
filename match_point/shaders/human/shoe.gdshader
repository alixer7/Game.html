shader_type spatial;
render_mode diffuse_burley;
uniform vec3 upper_color : source_color = vec3(0.95);
uniform vec3 sole_color : source_color = vec3(0.92, 0.9, 0.86);
uniform vec3 accent_color : source_color = vec3(0.1, 0.3, 0.8);
uniform sampler2D mesh_tex : hint_normal, filter_linear_mipmap, repeat_enable;

void fragment() {
	vec4 c = COLOR;
	vec3 col = mix(upper_color, accent_color, c.g);
	col = mix(col, sole_color, c.r);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.75, c.r);
	SPECULAR = 0.45;
	NORMAL_MAP = texture(mesh_tex, UV * 30.0).rgb;
	NORMAL_MAP_DEPTH = 0.5 * (1.0 - c.r);
}
