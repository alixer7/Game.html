shader_type spatial;
render_mode diffuse_burley;
// شعر قصير: خصلات دقيقة + لمعان متغير + حافة ناعمة
uniform vec3 hair_color : source_color = vec3(0.08, 0.06, 0.05);
uniform sampler2D strands : filter_linear_mipmap, repeat_enable;
uniform float coarse = 1.0;

void fragment() {
	float s = texture(strands, vec2(UV.x * 26.0 * coarse, UV.y * 5.0 * coarse)).r;
	float s2 = texture(strands, UV * 11.0 * coarse + vec2(0.37)).r;
	vec3 col = hair_color * (0.65 + 0.6 * s * s2);
	ALBEDO = col;
	ROUGHNESS = 0.55 + 0.3 * s;
	SPECULAR = 0.55;
	NORMAL_MAP = normalize(vec3(s - 0.5, s2 - 0.5, 1.4) * 0.5 + 0.5);
	NORMAL_MAP_DEPTH = 1.2;
}
