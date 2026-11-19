shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// UV.x = position along the car (0 front .. 1 rear), UV.y = section param (0 bottom .. 0.5 roof centre .. 1)
uniform vec3 paint : source_color = vec3(0.7, 0.05, 0.03);
uniform float metallic_flake = 0.55;
uniform float roughness_base = 0.32;
uniform float dirt = 0.0;
uniform float damage = 0.0;
uniform vec4 seams_u = vec4(0.30, 0.52, 0.72, -1.0);   // door / panel gap positions along the car
uniform vec2 seam_v = vec2(0.06, 0.24);                // vertical extent of door seams (section param)
uniform vec2 stripe = vec2(-1.0, 0.0);                // racing stripe: half-width (section param), intensity
uniform vec3 stripe_color : source_color = vec3(0.95);
uniform vec4 panel = vec4(-1.0, -1.0, 0.0, 0.0);       // two-tone panel: u0, u1, v0, v1
uniform vec3 panel_color : source_color = vec3(0.95);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec3 col = paint;
	float side_v = UV.y < 0.5 ? UV.y : 1.0 - UV.y;
	// racing stripe over the top centre
	if (stripe.x > 0.0) {
		float s = 1.0 - smoothstep(stripe.x - 0.004, stripe.x, abs(UV.y - 0.5));
		float gap = 1.0 - smoothstep(0.004, 0.008, abs(UV.y - 0.5));
		col = mix(col, stripe_color, s * (1.0 - gap) * stripe.y);
	}
	if (panel.x >= 0.0) {
		float pu = smoothstep(panel.x - 0.002, panel.x, UV.x) * (1.0 - smoothstep(panel.y, panel.y + 0.002, UV.x));
		float pv = smoothstep(panel.z - 0.003, panel.z, side_v) * (1.0 - smoothstep(panel.w, panel.w + 0.003, side_v));
		col = mix(col, panel_color, pu * pv);
	}
	// panel gaps
	float seam = 0.0;
	float aa = fwidth(UV.x) * 1.5 + 0.0005;
	for (int i = 0; i < 4; i++) {
		float u = seams_u[i];
		if (u < 0.0) continue;
		float d = abs(UV.x - u);
		seam = max(seam, (1.0 - smoothstep(0.0012, 0.0012 + aa, d)) * step(seam_v.x, side_v) * step(side_v, seam_v.y));
	}
	// hood / boot shut lines
	float hood = (1.0 - smoothstep(0.0, 0.004, abs(side_v - 0.43))) * step(UV.x, seams_u.x - 0.02);
	seam = max(seam, hood * 0.7);
	col *= 1.0 - seam * 0.75;
	// road dirt towards the sills
	float low = 1.0 - smoothstep(0.03, 0.16, side_v);
	float n = vnoise(UV * vec2(60.0, 40.0));
	col = mix(col, vec3(0.32, 0.27, 0.2), clamp(low * (0.15 + dirt) * (0.6 + 0.4 * n), 0.0, 0.85));
	// scratches from damage
	float scr = smoothstep(0.85, 0.95, vnoise(UV * vec2(300.0, 25.0))) * damage;
	col = mix(col, vec3(0.6), scr * 0.6);
	ALBEDO = col;
	METALLIC = metallic_flake;
	ROUGHNESS = clamp(roughness_base + low * dirt * 0.4 + scr * 0.3, 0.05, 1.0);
	SPECULAR = 0.6;
	CLEARCOAT = 1.0 - dirt * 0.5;
	CLEARCOAT_ROUGHNESS = 0.06 + damage * 0.3;
}
