shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = texture(noise_tex, wp.xz * 0.03 + vec2(TIME * 0.01, TIME * 0.007)).r;
	float n2 = texture(noise_tex, wp.xz * 0.11 - vec2(TIME * 0.02, 0.0)).r;
	float k = smoothstep(0.35, 0.75, n * 0.6 + n2 * 0.4);
	ALBEDO = mix(vec3(0.35, 0.04, 0.0), vec3(2.4, 0.9, 0.15), k);
}
