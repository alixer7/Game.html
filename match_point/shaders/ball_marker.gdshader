shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// مؤشر الكرة على الأرض: يقع عمودياً تحت الكرة ويتحرك معها ما دامت في الهواء.
//  - حلقة خارجية ثابتة + نقطة مركزية = موضع الكرة على الأرض
//  - حلقة داخلية «للارتفاع»: كبيرة والكرة عالية، وتنكمش نحو المركز كلما اقتربت الكرة من الأرض
//    (تلتقي بالنقطة لحظة الارتداد) — تساعد على قراءة توقيت الهبوط
//  - إطار داكن رفيع ليبقى واضحاً فوق الخطوط البيضاء والتراب والعشب
uniform vec4 color : source_color = vec4(0.86, 0.96, 0.24, 1.0);
uniform float alpha = 1.0;
uniform float height_k = 0.5;    // 0 على الأرض ... 1 عالية جداً
uniform float pulse = 0.0;

float band(float d, float r, float w) {
	return smoothstep(r - w - 0.035, r - w, d) * (1.0 - smoothstep(r + w, r + w + 0.035, d));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float outer = band(d, 0.80, 0.045);
	float outer_dark = band(d, 0.80, 0.11) * (1.0 - outer);
	float ri = 0.16 + 0.56 * clamp(height_k, 0.0, 1.0);
	float inner = band(d, ri, 0.03) * 0.75;
	float dot_c = 1.0 - smoothstep(0.09, 0.15, d);
	float dot_dark = (1.0 - smoothstep(0.15, 0.22, d)) * (1.0 - dot_c);
	float lit = max(max(outer, inner), dot_c);
	float dark = max(outer_dark, dot_dark) * 0.55;
	vec3 col = mix(vec3(0.02, 0.03, 0.04), color.rgb * (0.92 + 0.08 * sin(pulse)), lit / max(lit + dark, 0.0001));
	ALBEDO = col;
	ALPHA = clamp(lit + dark, 0.0, 1.0) * alpha * color.a;
}
