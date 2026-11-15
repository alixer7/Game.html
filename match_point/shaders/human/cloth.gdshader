shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// قماش رياضي: لون أساسي + حواف + شريط جانبي + نسيج دقيق + لمعان حافّي
uniform vec3 base_color : source_color = vec3(0.9);
uniform vec3 back_color : source_color = vec3(0.9);
uniform vec3 trim_color : source_color = vec3(0.2);
uniform vec3 stripe_color : source_color = vec3(0.2);
uniform float use_back = 0.0;
uniform float use_stripe = 0.0;
uniform sampler2D weave : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D folds : hint_normal, filter_linear_mipmap, repeat_enable;
// رفرفة القماش المرتخي (b في لون الرأس) مع الحركة والريح
uniform float flutter = 0.25;
uniform vec3 sway = vec3(0.0);
varying float loose;

void vertex() {
	loose = COLOR.b;
	float ph = TIME * (7.0 + 5.0 * flutter) + VERTEX.y * 17.0 + VERTEX.x * 11.0 + VERTEX.z * 7.0;
	float w = sin(ph) * 0.6 + sin(ph * 1.73 + 1.3) * 0.4;
	VERTEX += NORMAL * w * loose * (0.0025 + 0.0075 * flutter);
	// القماش يتأخر عن حركة الجسم (قصور ذاتي)
	VERTEX += sway * loose * loose;
}

void fragment() {
	vec4 c = COLOR;
	vec3 col = mix(base_color, back_color, c.g * use_back);
	col = mix(col, stripe_color, c.g * use_stripe);
	col = mix(col, trim_color, c.r);
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	ALBEDO = col * (0.94 + 0.06 * texture(weave, UV * 9.0).g);
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
	vec3 fn = texture(folds, UV * vec2(1.6, 0.8)).rgb;
	NORMAL_MAP = normalize(mix(fn, texture(weave, UV * 22.0).rgb, 0.4 - 0.15 * loose));
	NORMAL_MAP_DEPTH = 0.55 + 0.5 * loose;
	// ظل خفيف داخل الثنيات
	ALBEDO *= 1.0 - 0.12 * loose * (1.0 - fn.b);
	EMISSION = col * rim * 0.07;
	if (!FRONT_FACING) {
		ALBEDO *= 0.55;
	}
}
