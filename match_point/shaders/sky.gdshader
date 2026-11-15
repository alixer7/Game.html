shader_type sky;
// سماء نهارية: تدرّج + هالة شمس + غيوم ركامية ثابتة (بلا تحريك حتى لا تُعاد حسابات الانعكاس كل إطار)
uniform vec3 top_color : source_color = vec3(0.13, 0.33, 0.70);
uniform vec3 horizon_color : source_color = vec3(0.64, 0.78, 0.93);
uniform vec3 ground_color : source_color = vec3(0.30, 0.33, 0.37);
uniform vec3 sun_dir = vec3(0.38, 0.82, 0.42);
uniform sampler2D cloud_tex : repeat_enable, filter_linear_mipmap;
uniform float cloud_cover = 0.5;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(h, 0.55));
	vec3 sd = normalize(sun_dir);
	float sdot = max(dot(d, sd), 0.0);
	col += vec3(1.0, 0.92, 0.75) * (pow(sdot, 350.0) * 6.0 + pow(sdot, 12.0) * 0.22);
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.18) * 0.16;
		float c = texture(cloud_tex, uv).r * 0.62 + texture(cloud_tex, uv * 2.7 + vec2(0.31, 0.17)).r * 0.27 + texture(cloud_tex, uv * 6.1).r * 0.11;
		float m = smoothstep(1.0 - cloud_cover * 0.62, 1.0 - cloud_cover * 0.62 + 0.24, c) * smoothstep(0.0, 0.12, d.y);
		float lit = clamp(0.62 + 0.38 * texture(cloud_tex, uv + sd.xz * 0.012).r, 0.0, 1.0);
		vec3 cc = mix(vec3(0.64, 0.69, 0.78), vec3(1.0, 0.99, 0.96), lit) * (0.9 + 0.25 * pow(sdot, 4.0));
		col = mix(col, cc, m * 0.92);
	} else {
		col = mix(horizon_color * 0.85, ground_color, clamp(-d.y * 6.0, 0.0, 1.0));
	}
	COLOR = col;
}
