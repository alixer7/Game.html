shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// v8 terrain: 4-way vertex-colour splat (R,G,B,A weights) with world-space UVs and macro variation.
uniform sampler2D tex_r : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_g : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale_r = 0.11;
uniform float scale_g = 0.07;
uniform float scale_b = 0.10;
uniform float scale_a = 0.12;
uniform vec4 tint_r : source_color = vec4(1.0);
uniform vec4 tint_g : source_color = vec4(1.0);
uniform vec4 tint_b : source_color = vec4(1.0);
uniform vec4 tint_a : source_color = vec4(1.0);
uniform float macro_strength = 0.22;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 w = COLOR;
	float sum = max(0.001, w.r + w.g + w.b + w.a);
	w /= sum;
	vec2 uv = wpos.xz;
	vec3 c = texture(tex_r, uv * scale_r).rgb * tint_r.rgb * w.r
		+ texture(tex_g, uv * scale_g).rgb * tint_g.rgb * w.g
		+ texture(tex_b, uv * scale_b).rgb * tint_b.rgb * w.b
		+ texture(tex_a, uv * scale_a).rgb * tint_a.rgb * w.a;
	float macro = texture(tex_g, uv * 0.006).r * 0.6 + texture(tex_r, uv * 0.017 + vec2(0.37, 0.11)).g * 0.4;
	c *= mix(1.0, 0.72 + macro * 0.62, macro_strength * 4.0);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
