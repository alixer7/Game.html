shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Vertical light beam / updraft column for an open CylinderMesh centred on the origin.

uniform vec4 color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float energy = 1.6;
uniform float height = 20.0;
uniform float scroll = 0.5;
uniform float bidir = 0.0;
uniform float intensity = 1.0;

varying float v_t;
varying vec3 v_loc;

void vertex() {
	v_t = VERTEX.y / height + 0.5;
	v_loc = VERTEX;
}

void fragment() {
	float edge = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.5);
	float fade = (bidir > 0.5) ? sin(3.14159 * clamp(v_t, 0.0, 1.0)) : pow(clamp(1.0 - v_t, 0.0, 1.0), 1.3) * smoothstep(0.0, 0.03, v_t);
	float streak = 0.72 + 0.28 * sin(v_t * 38.0 - TIME * scroll * 10.0 + atan(v_loc.z, v_loc.x) * 3.0);
	float a = (0.1 + edge * 0.9) * fade * streak * intensity;
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
