shader_type spatial;

// Car body: paint + accent + glass + trim selected by vertex colour masks.
uniform vec3 paint : source_color = vec3(0.1, 0.4, 1.0);
uniform vec3 accent : source_color = vec3(0.9, 0.9, 0.95);
uniform float glow = 0.0;

varying vec4 masks;

void vertex() {
	masks = COLOR;
}

void fragment() {
	vec3 col = paint;
	float metal = 0.55;
	float rough = 0.28;
	col = mix(col, accent, masks.r);
	col = mix(col, vec3(0.015, 0.02, 0.035), masks.g);
	rough = mix(rough, 0.05, masks.g);
	metal = mix(metal, 0.8, masks.g);
	col = mix(col, vec3(0.025, 0.025, 0.03), masks.b);
	rough = mix(rough, 0.65, masks.b);
	metal = mix(metal, 0.2, masks.b);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = col * (0.06 + glow) + vec3(0.55, 0.65, 0.85) * rim * (0.28 + 0.4 * masks.g) * (1.0 - masks.b * 0.7);
}
