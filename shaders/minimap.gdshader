shader_type canvas_item;

uniform sampler2D map_tex : filter_linear_mipmap;
uniform vec2 center_uv = vec2(0.5);
uniform float rot = 0.0;
uniform float zoom = 0.12;
uniform vec4 ring_color : source_color = vec4(1.0, 0.45, 0.12, 0.9);

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p);
	vec2 q = vec2(cos(rot) * p.x - sin(rot) * p.y, sin(rot) * p.x + cos(rot) * p.y);
	vec2 uv = center_uv + q * zoom;
	vec4 c = texture(map_tex, uv);
	float inside = 1.0 - smoothstep(0.485, 0.5, d);
	float ring = smoothstep(0.46, 0.475, d) * inside;
	vec3 col = mix(c.rgb * 0.92, ring_color.rgb, ring * ring_color.a);
	// vignette
	col *= 1.0 - smoothstep(0.3, 0.48, d) * 0.25;
	COLOR = vec4(col, inside * 0.92);
}
