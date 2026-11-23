// Shared helpers for Wildspark Kart's stylized world shaders.
// Every world shader samples grass identically so road shoulders, banks and the
// terrain meet without visible seams.

uniform sampler2D g_grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 g_grass_tint_a : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 g_grass_tint_b : source_color = vec3(0.86, 1.04, 0.66);
uniform vec3 g_grass_tint_dry : source_color = vec3(1.12, 1.02, 0.62);
uniform float g_grass_scale = 0.11;

vec3 world_grass(vec3 wp) {
	vec2 uv = wp.xz;
	vec4 nz = texture(g_noise_tex, uv * 0.0035);
	float n2 = texture(g_noise_tex, uv * 0.021).g;
	vec3 a = texture(g_grass_tex, uv * g_grass_scale).rgb;
	// second, rotated & rescaled sample hides tiling
	vec2 ruv = vec2(uv.x * 0.8 - uv.y * 0.6, uv.x * 0.6 + uv.y * 0.8) * g_grass_scale * 0.43 + vec2(0.31, 0.77);
	vec3 b = texture(g_grass_tex, ruv).rgb;
	vec3 g = mix(a, b, smoothstep(0.38, 0.62, n2));
	g *= mix(g_grass_tint_a, g_grass_tint_b, smoothstep(0.25, 0.75, nz.r));
	g *= mix(vec3(1.0), g_grass_tint_dry, smoothstep(0.62, 0.9, nz.g) * 0.6);
	return g;
}

vec3 triplanar_tex(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	return texture(t, p.zy * s).rgb * w.x + texture(t, p.xz * s).rgb * w.y + texture(t, p.xy * s).rgb * w.z;
}

vec3 triplanar_normal(sampler2D t, vec3 p, vec3 n, float s) {
	// cheap whiteout-ish blend of tangent-space normals into a world-space normal
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	vec3 tx = texture(t, p.zy * s).rgb * 2.0 - 1.0;
	vec3 ty = texture(t, p.xz * s).rgb * 2.0 - 1.0;
	vec3 tz = texture(t, p.xy * s).rgb * 2.0 - 1.0;
	vec3 nx = vec3(n.x, tx.y + n.y, tx.x + n.z);
	vec3 ny = vec3(ty.x + n.x, n.y, ty.y + n.z);
	vec3 nz = vec3(tz.x + n.x, tz.y + n.y, n.z);
	return normalize(nx * w.x + ny * w.y + nz * w.z);
}
