shader_type sky;

// سماء ديناميكية: تدرج لوني حسب الوقت، شمس، قمر، نجوم، غيوم متحركة
uniform vec3 top_color : source_color = vec3(0.25, 0.45, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 ground_color : source_color = vec3(0.3, 0.3, 0.32);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float night = 0.0;
uniform float cloud_cover = 0.35;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col;
	if (y > 0.0) {
		col = mix(horizon_color, top_color, pow(y, 0.5));
	} else {
		col = mix(horizon_color, ground_color, clamp(pow(-y, 0.35), 0.0, 1.0));
	}
	float sd = dot(d, normalize(sun_dir));
	float day = 1.0 - night;
	col += sun_color * (pow(max(sd, 0.0), 6.0) * 0.28 + pow(max(sd, 0.0), 80.0) * 0.7) * day;
	col = mix(col, sun_color * 6.0, smoothstep(0.99955, 0.9997, sd) * day);
	if (!AT_CUBEMAP_PASS && night > 0.01 && y > 0.0) {
		vec3 p = d * 230.0;
		vec3 cell = floor(p);
		float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		if (h > 0.986) {
			vec3 cen = cell + 0.5 + (vec3(fract(h * 13.1), fract(h * 7.7), fract(h * 3.3)) - 0.5) * 0.6;
			float star = smoothstep(0.32, 0.0, length(p - cen)) * (h - 0.986) * 70.0;
			col += vec3(star) * night * smoothstep(0.0, 0.25, y) * (1.0 - cloud_cover * 0.9);
		}
	}
	float md = dot(d, normalize(moon_dir));
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9992, 0.9995, md) * night * 1.4;
	col += vec3(0.25, 0.3, 0.45) * pow(max(md, 0.0), 24.0) * night * 0.35;
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.12) * 0.3 + vec2(TIME * 0.0035, TIME * 0.002);
		float c1 = texture(cloud_tex, uv).r;
		float c2 = texture(cloud_tex, uv * 2.4 + vec2(0.31, 0.17)).r;
		float c = c1 * 0.7 + c2 * 0.3;
		float cov = smoothstep(1.0 - cloud_cover - 0.12, 1.0 - cloud_cover + 0.28, c);
		cov *= smoothstep(0.0, 0.1, y);
		vec3 cc = cloud_color * (0.72 + 0.28 * c2) + sun_color * pow(max(sd, 0.0), 8.0) * 0.25 * day;
		col = mix(col, cc, cov * 0.93);
	}
	COLOR = col;
}
