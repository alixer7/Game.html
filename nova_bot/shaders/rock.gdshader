shader_type spatial;
// Floating-island undersides, scenery rocks and hulls. COLOR.r = depth ratio (0 at the rim, 1 at the tip).
// style: 0 station hull (panel lines + lights), 1 crystal rock, 2 foundry slag (glowing cracks), 3 ice rock,
// 4 obsidian with energy veins.

uniform int style = 1;
uniform vec4 rock_a : source_color = vec4(0.3, 0.27, 0.35, 1.0);
uniform vec4 rock_b : source_color = vec4(0.16, 0.14, 0.2, 1.0);
uniform vec4 vein_color : source_color = vec4(1.0, 0.4, 0.9, 1.0);
uniform float vein_amount = 1.0;
uniform float use_depth = 1.0;

varying vec3 v_world;
varying float v_depth;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vn3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vn3(p) * a;
		p = p * 2.07 + 3.1;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = COLOR.r * use_depth;
}

void fragment() {
	float n = fbm3(v_world * 0.45);
	float strata = sin(v_world.y * 2.2 + n * 5.0) * 0.5 + 0.5;
	vec3 alb = mix(rock_b.rgb, rock_a.rgb, clamp(n * 0.9 + strata * 0.35, 0.0, 1.0));
	alb *= 1.0 - v_depth * 0.45;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emis = vec3(0.0);
	float ridge = 1.0 - abs(fbm3(v_world * 0.8 + 7.0) * 2.0 - 1.0);
	float vein = smoothstep(0.92, 0.99, ridge);
	if (style == 0) {
		float ln = smoothstep(0.05, 0.0, abs(fract(v_world.y * 0.9) - 0.5) - 0.45);
		alb = mix(rock_a.rgb, rock_b.rgb, 0.35 + v_depth * 0.5) * (1.0 - 0.25 * ln) * (0.92 + 0.08 * n);
		float lamp = step(0.97, hash13(floor(v_world * vec3(0.8, 0.9, 0.8)))) * ln;
		emis += vein_color.rgb * lamp * 2.0 * vein_amount;
		rough = 0.45;
		metal = 0.6;
	} else if (style == 2) {
		emis += vein_color.rgb * vein * vein_amount * (1.5 + v_depth * 2.0) * (0.7 + 0.3 * sin(TIME * 2.0 + n * 10.0));
		rough = 0.9;
	} else if (style == 3) {
		alb = mix(alb, vec3(0.55, 0.75, 0.95), 0.35 + v_depth * 0.4);
		rough = 0.35;
		emis += vein_color.rgb * vein * vein_amount * 0.35;
	} else if (style == 4) {
		alb *= 0.6;
		rough = 0.2;
		metal = 0.4;
		emis += vein_color.rgb * vein * vein_amount * (1.0 + v_depth * 1.5);
	} else {
		emis += vein_color.rgb * vein * vein_amount * (0.4 + v_depth * 0.9);
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
}
