shader_type sky;
render_mode use_debanding;

uniform vec3 top_color : source_color = vec3(0.20, 0.46, 0.86);
uniform vec3 mid_color : source_color = vec3(0.47, 0.70, 0.93);
uniform vec3 horizon_color : source_color = vec3(0.84, 0.90, 0.93);
uniform vec3 ground_color : source_color = vec3(0.36, 0.45, 0.38);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 cloud_shadow : source_color = vec3(0.62, 0.70, 0.84);
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform float cloud_speed = 0.0035;
uniform float cloud_cover = 0.45;
uniform float sun_size = 0.9995;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.25, h));
		col = mix(col, top_color, smoothstep(0.2, 0.9, h));
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.2, -h));
	}
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * (pow(max(sd, 0.0), 6.0) * 0.18 + pow(max(sd, 0.0), 64.0) * 0.35);
		col = mix(col, vec3(1.0, 0.98, 0.9) * 3.0, smoothstep(sun_size - 0.0004, sun_size, sd));
	}
	if (h > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 cuv = d.xz / (h + 0.12) * 0.22;
		float c1 = texture(cloud_tex, cuv + vec2(TIME * cloud_speed, 0.0)).r;
		float c2 = texture(cloud_tex, cuv * 2.1 + vec2(TIME * cloud_speed * 1.6, 0.31)).r;
		float c = c1 * 0.75 + c2 * 0.35;
		float a = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, c) * smoothstep(0.0, 0.18, h);
		float lit = 0.6;
		if (LIGHT0_ENABLED) {
			lit = clamp(0.55 + 0.45 * dot(d, LIGHT0_DIRECTION), 0.0, 1.0);
		}
		vec3 cc = mix(cloud_shadow, cloud_light, smoothstep(0.2, 0.9, c * lit + 0.2));
		col = mix(col, cc, a * 0.92);
	} else if (h > 0.0) {
		// cheap cubemap pass for ambient/reflections: soft average cloud colour
		col = mix(col, mix(cloud_shadow, cloud_light, 0.6), 0.25 * smoothstep(0.0, 0.2, h));
	}
	COLOR = col;
}
