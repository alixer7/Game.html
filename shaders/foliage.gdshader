shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind = 0.25;
uniform float alpha_cut = 0.45;
uniform bool use_texture = true;

varying float v_var;
varying float v_h;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_var = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	v_h = VERTEX.y;
	float bend = max(VERTEX.y - 1.0, 0.0) * 0.012 * wind;
	float t = TIME * 1.1 + origin.x * 0.05 + origin.z * 0.07;
	VERTEX.x += sin(t) * bend * VERTEX.y * 0.3 + sin(t * 3.7 + VERTEX.y) * bend * 0.4 * COLOR.a;
	VERTEX.z += cos(t * 0.8) * bend * VERTEX.y * 0.2 + cos(t * 4.1 + VERTEX.x) * bend * 0.4 * COLOR.a;
}

void fragment() {
	vec4 c = use_texture ? texture(leaf_tex, UV) : vec4(1.0);
	vec3 col = c.rgb * COLOR.rgb * tint;
	col *= mix(vec3(0.82, 0.9, 0.8), vec3(1.12, 1.08, 0.95), v_var);
	// darker inside the crown (fake occlusion stored in vertex colour brightness)
	ALBEDO = col;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.45;
}
