shader_type canvas_item;
render_mode blend_add;

uniform float amount = 0.0;
uniform vec3 tint : source_color = vec3(0.7, 0.85, 1.0);

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 p = UV - 0.5;
	p.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(p);
	float a = atan(p.y, p.x);
	float seg = floor(a * 40.0);
	float h = hash(seg);
	float speed = fract(h * 7.0 + TIME * (1.5 + h * 2.0));
	float streak = smoothstep(0.985, 1.0, fract(a * 40.0 / 6.2831 * 6.2831)) * 0.0;
	float line = step(0.82, h) * smoothstep(0.25, 0.6, r) * smoothstep(0.0, 0.15, fract(r * 1.5 - speed)) * (1.0 - smoothstep(0.15, 0.35, fract(r * 1.5 - speed)));
	float vign = smoothstep(0.35, 0.85, r);
	COLOR = vec4(tint * (line * 0.5 + vign * 0.18) * amount, 1.0);
}
