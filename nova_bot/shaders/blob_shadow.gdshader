shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Soft contact shadow + landing ring drawn on a flat quad under the player.

uniform float strength = 0.55;
uniform float ring = 0.0;
uniform vec4 ring_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float blob = smoothstep(1.0, 0.25, r) * strength;
	float rg = smoothstep(0.1, 0.0, abs(r - 0.78)) * ring;
	ALBEDO = mix(vec3(0.0), ring_color.rgb * 2.0, clamp(rg, 0.0, 1.0));
	ALPHA = clamp(blob + rg, 0.0, 1.0);
}
