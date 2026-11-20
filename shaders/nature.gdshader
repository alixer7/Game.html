shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// مادة عامة للطبيعة: أشجار، صخور، نباتات. تستخدم ألوان الرؤوس + تفاصيل ضوضاء ثلاثية الإسقاط + رياح.
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.3;
uniform float wind_mult = 1.0;
uniform float detail_strength = 0.3;
uniform float detail_scale = 1.5;
uniform float roughness_val = 0.9;
uniform float specular_val = 0.3;
uniform float metallic_val = 0.0;
uniform float emission_val = 0.0;
uniform float backlight_val = 0.0;
uniform float hue_var = 0.0;
uniform float wetness = 0.0;
uniform float snow = 0.0;
uniform float cold_z0 = 380.0;
uniform float cold_z1 = 680.0;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;
varying float inst_hue;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	inst_hue = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	if (wind_strength > 0.0) {
		float h = max(VERTEX.y, 0.0);
		float ph = origin.x * 0.31 + origin.z * 0.23;
		float t = TIME * wind_speed;
		float sway = sin(t + ph) * 0.6 + sin(t * 0.47 + ph * 1.7) * 0.4;
		vec3 off = vec3(sway, 0.0, cos(t * 0.8 + ph * 1.3) * 0.5) * h * 0.035;
		off += vec3(sin(t * 3.3 + wpos.y * 2.1 + wpos.x), sin(t * 2.7 + wpos.z * 1.7) * 0.5, cos(t * 3.1 + wpos.z)) * 0.025 * min(h, 4.0);
		VERTEX += off * wind_strength * wind_mult;
	}
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = COLOR.rgb;
	vec3 an = abs(wnrm) + 0.001;
	an /= (an.x + an.y + an.z);
	float d = texture(detail_tex, wpos.zy * detail_scale).r * an.x
		+ texture(detail_tex, wpos.xz * detail_scale).r * an.y
		+ texture(detail_tex, wpos.xy * detail_scale).r * an.z;
	col *= mix(1.0, 0.5 + d * 1.0, detail_strength);
	col *= 1.0 + (inst_hue - 0.5) * hue_var;
	float cold = clamp(smoothstep(cold_z0, cold_z1, -wpos.z) + smoothstep(58.0, 74.0, wpos.y), 0.0, 1.0);
	float sn = max(snow, cold * 0.85) * smoothstep(0.35, 0.8, wnrm.y);
	col = mix(col, vec3(0.8, 0.82, 0.86), sn);
	ALBEDO = col * (1.0 - wetness * 0.22 * (1.0 - sn));
	ROUGHNESS = mix(roughness_val, roughness_val * 0.45, wetness);
	SPECULAR = specular_val + wetness * 0.2;
	METALLIC = metallic_val;
	EMISSION = COLOR.rgb * emission_val;
	BACKLIGHT = vec3(backlight_val) * col;
}
