shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Generic world-space tri-planar material sampling one layer of the surface array
// (0 asphalt, 1 cobble, 2 gravel, 3 concrete, 4 sidewalk tiles, 5 masonry).
uniform sampler2DArray surf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer = 3.0;
uniform float scale = 0.25;
uniform vec3 tint : source_color = vec3(1.0);
uniform float dirt = 0.25;
uniform bool use_vertex_color = false;

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 ref = abs(NORMAL.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
	TANGENT = normalize(cross(ref, NORMAL));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	vec3 bw = pow(abs(v_wn), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 a = texture(surf_albedo, vec3(v_world.zy * scale, layer)) * bw.x
		+ texture(surf_albedo, vec3(v_world.xz * scale, layer)) * bw.y
		+ texture(surf_albedo, vec3(v_world.xy * scale, layer)) * bw.z;
	vec3 n = texture(surf_normal, vec3(v_world.zy * scale, layer)).rgb * bw.x
		+ texture(surf_normal, vec3(v_world.xz * scale, layer)).rgb * bw.y
		+ texture(surf_normal, vec3(v_world.xy * scale, layer)).rgb * bw.z;
	vec3 col = a.rgb * tint;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	// ground grime towards the bottom of vertical surfaces
	col *= 1.0 - dirt * 0.15 * (1.0 - abs(v_wn.y));
	ALBEDO = col;
	ROUGHNESS = a.a;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.9;
}
