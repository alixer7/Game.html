shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;
// شعر قصير: خصلات دقيقة + خط شعر طبيعي يتكسّر إلى خصلات (COLOR.r = 0 عند الحافة ← 1 في الداخل)
// مع قصّ ألفا (بلا مشاكل ترتيب الشفافية) + لمعان مزاح على امتداد الخصلات (تقريب Kajiya-Kay)
uniform vec3 hair_color : source_color = vec3(0.08, 0.06, 0.05);
uniform sampler2D strands : filter_linear_mipmap, repeat_enable;
uniform float coarse = 1.0;
varying vec3 tang;

void vertex() {
	// اتجاه الخصلات: من التاج نحو الأسفل والأمام تقريباً (في فضاء النموذج)
	tang = normalize((MODELVIEW_MATRIX * vec4(0.0, -1.0, -0.35, 0.0)).xyz);
}

void fragment() {
	float s = texture(strands, vec2(UV.x * 26.0 * coarse, UV.y * 5.0 * coarse)).r;
	float s2 = texture(strands, UV * 11.0 * coarse + vec2(0.37)).r;
	float s3 = texture(strands, vec2(UV.x * 61.0, UV.y * 9.0) + vec2(0.11, 0.53)).r;
	float edge = clamp(COLOR.r, 0.0, 1.0);
	// عند الحافة: الخصلات المتفرقة فقط تبقى ظاهرة
	ALPHA = clamp(edge * 1.7 + (s3 - 0.5) * 1.3 + 0.05, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 col = hair_color * (0.62 + 0.62 * s * s2) * mix(0.8, 1.0, edge);
	ALBEDO = col;
	ROUGHNESS = 0.5 + 0.3 * s;
	SPECULAR = 0.35;
	NORMAL_MAP = normalize(vec3(s - 0.5, s2 - 0.5, 1.4) * 0.5 + 0.5);
	NORMAL_MAP_DEPTH = 1.2;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += mix(0.25, 1.0, ndl) * ndl * ATTENUATION * LIGHT_COLOR / PI;
	// لمعتان على امتداد الخصلات: أولى بيضاء مزاحة للأعلى وثانية ملوّنة أعرض
	vec3 H = normalize(VIEW + LIGHT);
	// المماس يتبع سطح الرأس فتتكوّن حزمة لمعان ضيقة بدل إضاءة موحّدة
	vec3 T = normalize(tang - NORMAL * dot(tang, NORMAL));
	vec3 T1 = normalize(T + NORMAL * 0.15);
	vec3 T2 = normalize(T - NORMAL * 0.10);
	float th1 = dot(T1, H);
	float th2 = dot(T2, H);
	float sp1 = pow(sqrt(max(1.0 - th1 * th1, 0.0)), 160.0);
	float sp2 = pow(sqrt(max(1.0 - th2 * th2, 0.0)), 40.0);
	SPECULAR_LIGHT += (sp1 * 0.05 + sp2 * 0.35 * ALBEDO) * ndl * ATTENUATION * LIGHT_COLOR;
}
