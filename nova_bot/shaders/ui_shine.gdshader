shader_type canvas_item;
// Animated glass sheen for panels / logo: a soft diagonal highlight sweeping across the rect.

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float speed = 0.35;
uniform float width = 0.18;
uniform float strength = 0.22;

void fragment() {
	float t = fract(TIME * speed);
	float x = (UV.x + UV.y * 0.35) - (t * 2.6 - 0.8);
	float band = smoothstep(width, 0.0, abs(x));
	COLOR = vec4(tint.rgb, band * strength);
}
