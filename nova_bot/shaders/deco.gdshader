shader_type spatial;
// Scenery rocks / pylons / crystals: dark body with a coloured fresnel rim and a faint height gradient.

uniform vec4 base : source_color = vec4(0.07, 0.09, 0.16, 1.0);
uniform vec4 rim_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float rim_pow = 3.0;
uniform float rim_energy = 1.4;
uniform float glow = 0.0;

varying float v_y;

void vertex() {
	v_y = VERTEX.y;
}

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_pow);
	ALBEDO = base.rgb * (0.8 + 0.4 * smoothstep(-1.0, 1.0, v_y));
	METALLIC = 0.25;
	ROUGHNESS = 0.55;
	EMISSION = rim_color.rgb * (f * rim_energy + glow);
}
