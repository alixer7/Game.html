class_name CameraRig
extends Node3D
## كاميرا البث التلفزيوني خلف اللاعب، مع متابعة ناعمة للاعب والكرة.

enum Mode { BROADCAST, CLOSE, ORBIT }

var cam: Camera3D
var player: TennisPlayer
var ball: TennisBall
var mode: int = Mode.BROADCAST
var _pos := Vector3(0, 6.4, 25.5)
var _look := Vector3(0, 0.8, -2.0)
var _orbit := 0.0
var _shake := 0.0
var height_k := 0.5      # 0 مسطحة .. 1 مرتفعة
var zoom_k := 0.5        # 0 بعيدة .. 1 قريبة من الملعب
var arena: Arena


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # تبقى تتحدث أثناء الإيقاف المؤقت لمعاينة إعدادات الكاميرا
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.3
	cam.far = 160.0
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(_pos, _look, Vector3.UP)


func snap() -> void:
	var t := _targets()
	_pos = t[0]
	_look = t[1]
	cam.fov = float(t[2])
	cam.look_at_from_position(_pos, _look, Vector3.UP)
	if arena != null:
		arena.set_camera_view(_pos)


func _targets() -> Array:
	if mode == Mode.ORBIT or player == null:
		var r := 30.0
		return [Vector3(sin(_orbit) * r, 9.5, cos(_orbit) * r * 1.15), Vector3(0, 0.5, 0), 34.0]
	var s := float(player.side)
	var px := player.position.x
	var pz := player.position.z * s
	var bx := ball.st.pos.x if ball != null else 0.0
	if mode == Mode.CLOSE:
		var p := Vector3(px * 0.75, 3.3, (maxf(pz, 9.0) + 7.2) * s)
		return [p, Vector3(px * 0.45 + bx * 0.15, 1.0, -4.0 * s), 52.0]
	# --- كاميرا البث القابلة للتخصيص ---
	# الارتفاع يحدد زاوية النظر (مسطحة ← مرتفعة)، والتقريب يحدد بُعد الكاميرا عن الملعب.
	# بعدها يُضبط الميل ومجال الرؤية تلقائياً ليبقى اللاعبان والملعب كله داخل الإطار.
	var elev := deg_to_rad(lerpf(4.0, 11.5, height_k * 2.0) if height_k < 0.5 else lerpf(11.5, 31.0, (height_k - 0.5) * 2.0))
	var dist := lerpf(39.0, 28.5, zoom_k * 2.0) if zoom_k < 0.5 else lerpf(28.5, 17.5, (zoom_k - 0.5) * 2.0)
	var cz := -2.4 + dist * cos(elev)
	var cy := maxf(0.7 + dist * sin(elev), 2.5)
	var back := clampf((pz - 12.6) * 0.6, -1.2, 3.6)
	cz = maxf(cz + back, pz + 3.4)
	cy += back * 0.25
	# أقرب نقطة يجب أن تظهر (قدما اللاعب القريب) وأبعد نقطة (خلف خط القاعدة البعيد)
	var near_z := maxf(pz, Court.HALF_LENGTH - 1.0) + 0.8
	var a_near := atan2(cy + 0.05, maxf(cz - near_z, 0.5))
	var a_far := atan2(cy - 2.1, cz + Court.HALF_LENGTH + 2.6)
	var vfov := clampf(rad_to_deg(a_near - a_far) + 7.0, 24.0, 84.0)
	# قدما اللاعب القريب تبقيان فوق الحافة السفلية بهامش ثابت، والمساحة الزائدة تذهب لأعلى الصورة (المدرجات والسماء)
	var pitch := a_near - deg_to_rad(vfov * 0.5 - 3.5)
	var look_d := cz + 2.4
	var p2 := Vector3(px * 0.36, cy, cz * s)
	return [p2, Vector3(px * 0.22 + bx * 0.10, cy - tan(pitch) * look_d, -2.4 * s), vfov]


func _process(dt: float) -> void:
	if mode == Mode.ORBIT:
		_orbit += dt * 0.12
	var t := _targets()
	var k := clampf(dt * 3.2, 0.0, 1.0)
	if mode == Mode.ORBIT:
		k = 1.0
	_pos = _pos.lerp(t[0], k)
	_look = _look.lerp(t[1], k)
	cam.fov = lerpf(cam.fov, float(t[2]), k)
	cam.look_at_from_position(_pos, _look, Vector3.UP)
	if arena != null:
		arena.set_camera_view(_pos)
