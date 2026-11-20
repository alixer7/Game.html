shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// عشب كثيف يتمايل مع الرياح ويختفي تدريجياً مع البعد
uniform float wind_mult = 1.0;
uniform float snow = 0.0;
uniform float fade_dist = 48.0;

varying float cold;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = VERTEX.y;
	float t = TIME * 1.7;
	float s = sin(t + wp.x * 0.42 + wp.z * 0.31) * 0.55 + sin(t * 2.3 + wp.x * 1.3) * 0.25;
	VERTEX.x += s * h * 0.2 * wind_mult;
	VERTEX.z += cos(t * 0.9 + wp.z * 0.5) * h * 0.12 * wind_mult;
	cold = clamp(smoothstep(380.0, 680.0, -wp.z) + smoothstep(58.0, 74.0, wp.y), 0.0, 1.0);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = length(wp - cam);
	VERTEX.y *= 1.0 - smoothstep(fade_dist * 0.65, fade_dist, dist);
}

void fragment() {
	vec3 col = COLOR.rgb;
	col = mix(col, vec3(0.8, 0.82, 0.86), max(snow, cold * 0.7) * 0.85);
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 0.88;
	SPECULAR = 0.15;
	BACKLIGHT = col * 0.4;
}
