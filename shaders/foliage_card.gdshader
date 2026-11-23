shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

// Alpha-scissored leaf cards (canopy fringes, ferns, reeds, hanging vines).
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 backlight_color : source_color = vec3(0.35, 0.5, 0.1);
uniform float wind_strength = 0.18;
uniform float wind_speed = 1.5;
uniform float alpha_cut = 0.45;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float ph = dot(origin, vec3(0.11, 0.0, 0.19));
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * wind_speed + ph + wp.y * 0.4 + wp.x * 0.2) * 0.6 + sin(TIME * wind_speed * 2.9 + ph * 2.1 + wp.z * 0.5) * 0.4;
	float sway = COLOR.a;
	VERTEX.x += w * wind_strength * sway;
	VERTEX.y += w * wind_strength * sway * 0.3;
	VERTEX.z += w * wind_strength * sway * 0.6;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * tint * 1.25;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.85;
	BACKLIGHT = backlight_color;
}
