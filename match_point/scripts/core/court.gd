class_name Court
extends RefCounted
## أبعاد الملعب الرسمية (ITF) وخصائص الأرضيات.
## الإحداثيات: X عرضي، Z طولي (الشبكة عند z=0)، Y للأعلى.
## الجانب side = +1 للاعب القريب من الكاميرا (z>0) و -1 للبعيد.

const HALF_LENGTH := 11.885      # 23.77 / 2
const SINGLES_HALF_W := 4.115    # 8.23 / 2
const DOUBLES_HALF_W := 5.485    # 10.97 / 2
const SERVICE_LINE := 6.40
const NET_H_CENTER := 0.914
const NET_H_POST := 1.07
const POST_X := 6.40             # 0.914 م خارج خط الزوجي
const LINE_W := 0.05
const BASELINE_W := 0.10
const BALL_R := 0.0335
## هامش ملامسة الكرة للخط (الكرة تنضغط عند الارتطام فتلمس الخط)
const LINE_TOUCH := 0.028

## حدود منطقة اللعب (الجدران الخلفية والجانبية)
const ARENA_HALF_W := 10.2
const ARENA_HALF_L := 19.2

enum Surface { HARD, CLAY, GRASS }

## e: معامل الارتداد العمودي، mu: معامل الاحتكاك الانزلاقي
## القيم مبنية على قياسات ITF Court Pace Rating
const SURFACES := {
	Surface.HARD: {"name": "صلبة", "e": 0.79, "mu": 0.62, "roll": 0.05, "noise": 0.0},
	Surface.CLAY: {"name": "ترابية", "e": 0.84, "mu": 0.78, "roll": 0.07, "noise": 0.035},
	Surface.GRASS: {"name": "عشبية", "e": 0.735, "mu": 0.50, "roll": 0.09, "noise": 0.05},
}


static func net_height(x: float) -> float:
	var t: float = clampf(absf(x) / POST_X, 0.0, 1.0)
	return NET_H_CENTER + (NET_H_POST - NET_H_CENTER) * t * t


## هل النقطة داخل ملعب الفردي في جهة side؟
static func in_singles(p: Vector3, side: int) -> bool:
	if p.z * side < -LINE_TOUCH:
		return false
	return absf(p.x) <= SINGLES_HALF_W + LINE_TOUCH and absf(p.z) <= HALF_LENGTH + LINE_TOUCH


## هل النقطة داخل مربع الإرسال الصحيح؟
## server_side: جهة المُرسل، deuce: الإرسال من اليمين
static func in_service_box(p: Vector3, server_side: int, deuce: bool) -> bool:
	var recv := -server_side
	if p.z * recv < -LINE_TOUCH or absf(p.z) > SERVICE_LINE + LINE_W * 0.5 + LINE_TOUCH:
		return false
	# المرسل من اليمين يقف عند x*server_side > 0 ويرسل قطرياً إلى x*server_side < 0
	var sx := p.x * server_side
	if deuce:
		return sx <= LINE_W * 0.5 + LINE_TOUCH and sx >= -(SINGLES_HALF_W + LINE_TOUCH)
	return sx >= -(LINE_W * 0.5 + LINE_TOUCH) and sx <= SINGLES_HALF_W + LINE_TOUCH


## مسافة الخروج عن الملعب (موجبة = خارج) — للإحصاءات وقرارات الذكاء الاصطناعي
static func out_distance(p: Vector3, side: int) -> float:
	var dx := absf(p.x) - SINGLES_HALF_W
	var dz := p.z * side - HALF_LENGTH
	var dn := -p.z * side
	return maxf(maxf(dx, dz), dn)
