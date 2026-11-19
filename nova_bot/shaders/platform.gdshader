shader_type spatial;
// Futuristic tech platform: dark panels, glowing edges, emissive top grid.
// Works for box (cyl = 0) and cylinder (cyl = 1, half_size.x = radius) meshes centred on the origin.

uniform vec3 half_size = vec3(2.0, 0.5, 2.0);
uniform vec4 base_color : source_color = vec4(0.05, 0.07, 0.13, 1.0);
uniform vec4 top_color : source_color = vec4(0.09, 0.12, 0.21, 1.0);
uniform vec4 edge_color : source_color = vec4(0.1, 0.85, 1.0, 1.0);
uniform float edge_width = 0.09;
uniform float edge_energy = 2.4;
uniform float grid_cell = 1.0;
uniform float cyl = 0.0;
uniform float pulse = 1.0;

varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float top = smoothstep(0.7, 0.95, wn.y);
	float edge_d;
	if (cyl > 0.5) {
		float r = length(v_local.xz);
		float d_side = half_size.x - r;
		float d_cap = half_size.y - abs(v_local.y);
		edge_d = (abs(wn.y) > 0.5) ? d_side : d_cap;
	} else {
		vec3 d = half_size - abs(v_local);
		float m1 = min(d.x, min(d.y, d.z));
		float m3 = max(d.x, max(d.y, d.z));
		edge_d = d.x + d.y + d.z - m1 - m3;
	}
	float edge = 1.0 - smoothstep(edge_width * 0.5, edge_width, edge_d);
	float halo = exp(-max(edge_d, 0.0) / (edge_width * 5.0));

	vec2 gp = v_local.xz / grid_cell;
	vec2 gl = abs(fract(gp - 0.5) - 0.5) / max(fwidth(gp), vec2(0.0001));
	float grid = 1.0 - clamp(min(gl.x, gl.y), 0.0, 1.0);
	vec2 cell = floor(gp);
	float chk = mod(cell.x + cell.y, 2.0);

	vec3 albedo = mix(base_color.rgb, top_color.rgb, top);
	albedo *= 1.0 + chk * 0.14 * top;
	float p = 1.0 + 0.22 * sin(TIME * 2.0 + v_world.x * 0.3 + v_world.z * 0.3) * pulse;

	vec3 emis = edge_color.rgb * (edge * edge_energy + halo * edge_energy * 0.12) * p;
	emis += edge_color.rgb * grid * top * 0.26;

	ALBEDO = albedo;
	METALLIC = 0.35;
	ROUGHNESS = mix(0.55, 0.3, top);
	EMISSION = emis;
}
