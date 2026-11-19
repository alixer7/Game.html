shader_type canvas_item;
// Screen overlay: soft vignette + damage / pickup flash.

uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform vec4 flash_color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float v = smoothstep(0.55, 1.5, length(p * vec2(0.95, 1.0)));
	float a = v * vignette + flash * (0.2 + v * 0.8);
	COLOR = vec4(mix(vec3(0.0), flash_color.rgb, flash), clamp(a, 0.0, 0.95));
}
