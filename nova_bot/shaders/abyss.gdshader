shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Endless neon grid far below the platforms (follows the camera, grid is anchored in world space).

uniform vec4 line_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform vec4 fill_color : source_color = vec4(0.02, 0.04, 0.12, 1.0);
uniform float cell = 8.0;
uniform float fade_dist = 300.0;
uniform vec2 center_xz = vec2(0.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 gp = v_world.xz / cell;
	vec2 g = abs(fract(gp - 0.5) - 0.5) / max(fwidth(gp), vec2(0.0001));
	float line = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	float d = length(v_world.xz - center_xz);
	float fade = 1.0 - smoothstep(fade_dist * 0.12, fade_dist, d);
	float pulse = 0.65 + 0.35 * sin(d * 0.07 - TIME * 1.6);
	ALBEDO = fill_color.rgb + line_color.rgb * line * 1.7 * pulse;
	ALPHA = (0.3 + line * 0.7) * fade;
}
