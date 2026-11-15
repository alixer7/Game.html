class_name Shot
extends RefCounted
## أنواع الضربات وخصائصها الفيزيائية (سرعات ودوران بمستوى المحترفين)

enum Type { FLAT, TOPSPIN, SLICE, LOB, DROP, VOLLEY, SMASH, SERVE_FLAT, SERVE_KICK, SERVE_SLICE }

const NAMES := {
	Type.FLAT: "مسطّحة", Type.TOPSPIN: "لولبية", Type.SLICE: "مقطوعة", Type.LOB: "عالية",
	Type.DROP: "ساقطة", Type.VOLLEY: "طائرة", Type.SMASH: "ساحقة",
	Type.SERVE_FLAT: "إرسال مسطّح", Type.SERVE_KICK: "إرسال كيك", Type.SERVE_SLICE: "إرسال سلايس",
}


static func is_serve(t: int) -> bool:
	return t >= Type.SERVE_FLAT


## power من 0 إلى 1. الدوران بالراديان/ث (1000 دورة/د ≈ 105 راد/ث)
## clear: أدنى خلوص فوق الشبكة، arc: زاوية القوس الثابتة (أو -1 لضربة مستقيمة)
## sig_az / sig_el: الانحراف المعياري الأساسي للخطأ بالدرجات، sig_v: نسبة خطأ السرعة
static func params(type: int, power: float, hand: int = 1) -> Dictionary:
	var p := clampf(power, 0.0, 1.0)
	match type:
		Type.FLAT:
			return {"speed": lerpf(25.0, 41.0, p), "top": lerpf(70.0, 115.0, p), "side": 0.0, "gyro": 0.0,
				"clear": 0.10, "arc": -1.0, "sig_az": 1.25, "sig_el": 0.70, "sig_v": 0.025}
		Type.TOPSPIN:
			return {"speed": lerpf(21.0, 34.5, p), "top": lerpf(240.0, 345.0, p), "side": 0.0, "gyro": 0.0,
				"clear": 0.20, "arc": -1.0, "sig_az": 1.25, "sig_el": 0.95, "sig_v": 0.025}
		Type.SLICE:
			return {"speed": lerpf(16.0, 27.0, p), "top": lerpf(-170.0, -260.0, p), "side": 0.0, "gyro": 0.0,
				"clear": 0.12, "arc": -1.0, "sig_az": 1.15, "sig_el": 0.80, "sig_v": 0.025}
		Type.LOB:
			return {"speed": 20.0, "top": lerpf(40.0, 230.0, p), "side": 0.0, "gyro": 0.0,
				"clear": 1.8, "arc": deg_to_rad(lerpf(58.0, 45.0, p)), "sig_az": 1.5, "sig_el": 1.3, "sig_v": 0.03}
		Type.DROP:
			return {"speed": 10.0, "top": lerpf(-190.0, -270.0, p), "side": 0.0, "gyro": 0.0,
				"clear": 0.22, "arc": deg_to_rad(27.0), "sig_az": 1.5, "sig_el": 1.6, "sig_v": 0.04}
		Type.VOLLEY:
			return {"speed": lerpf(15.0, 27.0, p), "top": lerpf(-50.0, -95.0, p), "side": 0.0, "gyro": 0.0,
				"clear": 0.10, "arc": -1.0, "sig_az": 1.3, "sig_el": 0.95, "sig_v": 0.03}
		Type.SMASH:
			return {"speed": lerpf(36.0, 50.0, p), "top": 40.0, "side": 0.0, "gyro": 0.0,
				"clear": 0.15, "arc": -1.0, "sig_az": 1.5, "sig_el": 0.8, "sig_v": 0.03}
		Type.SERVE_FLAT:
			return {"speed": lerpf(50.0, 58.5, p), "top": lerpf(85.0, 110.0, p), "side": 45.0 * hand, "gyro": 0.0,
				"clear": 0.06, "arc": -1.0, "sig_az": 0.80, "sig_el": 0.60, "sig_v": 0.015}
		Type.SERVE_KICK:
			return {"speed": lerpf(38.0, 45.0, p), "top": lerpf(350.0, 450.0, p), "side": 110.0 * hand, "gyro": 180.0 * hand,
				"clear": 0.25, "arc": -1.0, "sig_az": 0.85, "sig_el": 0.62, "sig_v": 0.015}
		Type.SERVE_SLICE:
			return {"speed": lerpf(43.0, 51.0, p), "top": lerpf(70.0, 90.0, p), "side": lerpf(290.0, 340.0, p) * hand, "gyro": -40.0 * hand,
				"clear": 0.10, "arc": -1.0, "sig_az": 0.80, "sig_el": 0.52, "sig_v": 0.015}
	return {}
