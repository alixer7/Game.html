class_name TennisBall
extends Node3D
## كرة التنس: تشغّل المحاكاة الفيزيائية (120 خطوة/ث) وتوفّر تنبؤاً بالمسار للاعبين.

signal bounced(pos: Vector3, speed: float)
signal net_touched(kind: int)
signal prediction_changed

enum Mode { HELD, TOSS, FREE, FEED }

const DT := BallPhysics.DT

var st := BallPhysics.State.new()
var surf: Dictionary = Court.SURFACES[Court.Surface.HARD]
var mode := Mode.HELD
var clock := 0.0
var rng := RandomNumberGenerator.new()
var holder: Node = null
var bounces_since_hit := 0
var in_play := false
var hit_clock := 0.0            # زمن آخر ضربة
var sun_dir := Vector3(0.35, 0.85, 0.3).normalized()   # الاتجاه نحو الشمس

# --- التنبؤ (زمن العينة i = pred_t0 + (i+1)*DT) ---
var pred_t0 := 0.0
var pred_pos := PackedVector3Array()
var pred_vel := PackedVector3Array()
var pred_bounces := PackedByteArray()      # عدد الارتدادات منذ الضربة حتى هذه العينة
var pred_first_bounce := Vector3.ZERO
var pred_first_bounce_t := -1.0
var pred_has_bounce := false
var pred_net := 0

var _toss_p0 := Vector3.ZERO
var _toss_v0 := Vector3.ZERO
var _toss_t0 := 0.0
var _acc := 0.0
var _feed_p0 := Vector3.ZERO
var _feed_t0 := 0.0
var _feed_T := 1.0
var _feed_target := Vector3.ZERO
var _feed_arc := 1.5
var _mesh: MeshInstance3D
var _shadow: MeshInstance3D
var _streak: MeshInstance3D
var _spin_basis := Basis.IDENTITY
var _visual_scale := 1.25
# مؤشر الكرة على الأرض (يتبعها عمودياً وهي في الهواء) + مكان السقوط المتوقع (اختياري)
var _marker: MeshInstance3D
var _bounce_mk: MeshInstance3D
var _marker_mode := 1
var _marker_a := 0.0
var _bounce_a := 0.0
var _mk_t := 0.0


func _ready() -> void:
	rng.randomize()
	_visual_scale = float(Settings.get_v("ball_scale"))
	var sm := SphereMesh.new()
	sm.radius = BallPhysics.R
	sm.height = BallPhysics.R * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ball.gdshader")
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.scale = Vector3.ONE * _visual_scale
	add_child(_mesh)
	# ظل ناعم تحت الكرة (أساسي لإدراك العمق)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	_shadow = MeshInstance3D.new()
	_shadow.mesh = q
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/blob_shadow.gdshader")
	_shadow.material_override = smat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)
	# أثر الحركة السريعة (motion blur streak)
	var cm := CapsuleMesh.new()
	cm.radius = BallPhysics.R * 0.92
	cm.height = 1.0
	cm.radial_segments = 8
	cm.rings = 2
	_streak = MeshInstance3D.new()
	_streak.mesh = cm
	var stm := StandardMaterial3D.new()
	stm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stm.albedo_color = Color(0.85, 0.95, 0.25, 0.28)
	stm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streak.material_override = stm
	_streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streak.top_level = true
	_streak.visible = false
	add_child(_streak)
	_marker = _make_ground_quad("res://shaders/ball_marker.gdshader", 0.56)
	_bounce_mk = _make_ground_quad("res://shaders/bounce_marker.gdshader", 0.34)
	_marker_mode = int(Settings.get_v("ball_marker"))
	Settings.changed.connect(func() -> void: _marker_mode = int(Settings.get_v("ball_marker")))


func _make_ground_quad(shader_path: String, size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	add_child(mi)
	return mi


func set_visual_scale(s: float) -> void:
	_visual_scale = s
	if _mesh:
		_mesh.scale = Vector3.ONE * s


func hold(by: Node) -> void:
	mode = Mode.HELD
	holder = by
	in_play = false
	st.vel = Vector3.ZERO
	st.spin = Vector3.ZERO
	st.rolling = false
	_clear_prediction()


## رمية من جامع الكرات إلى اللاعب (قوس يتتبع يد اللاعب حتى يلتقطها)
func feed(from: Vector3, by: Node, flight: float) -> void:
	mode = Mode.FEED
	holder = by
	in_play = false
	_feed_p0 = from
	_feed_t0 = clock
	_feed_T = flight
	_feed_arc = 1.5
	st.pos = from
	st.spin = Vector3(4.0, 0, 0)
	_clear_prediction()


## رمية هادئة من اللاعب إلى جامع الكرات (بعد التقاطها من الأرض)
func throw_to(target: Vector3, flight: float) -> void:
	mode = Mode.FEED
	_feed_p0 = st.pos
	_feed_t0 = clock
	_feed_T = flight
	_feed_target = target
	_feed_arc = 1.1
	holder = null
	in_play = false
	st.spin = Vector3(-6.0, 0, 0)
	_clear_prediction()


func feed_time_left() -> float:
	return maxf(_feed_t0 + _feed_T - clock, 0.0)


func toss(from: Vector3, v0: Vector3) -> void:
	mode = Mode.TOSS
	_toss_p0 = from
	_toss_v0 = v0
	_toss_t0 = clock
	st.pos = from
	st.vel = v0
	st.spin = Vector3(2.0, 0, 0)


func toss_pos_at(t_abs: float) -> Vector3:
	var t := t_abs - _toss_t0
	return _toss_p0 + _toss_v0 * t + Vector3(0, -0.5 * BallPhysics.G * t * t, 0)


func launch(pos: Vector3, vel: Vector3, spin: Vector3) -> void:
	mode = Mode.FREE
	st.pos = pos
	st.vel = vel
	st.spin = spin
	st.rolling = false
	bounces_since_hit = 0
	in_play = true
	hit_clock = clock
	_predict()


func _clear_prediction() -> void:
	pred_pos = PackedVector3Array()
	pred_vel = PackedVector3Array()
	pred_bounces = PackedByteArray()
	pred_has_bounce = false
	pred_first_bounce_t = -1.0
	pred_net = 0


func _predict() -> void:
	var s := st.copy()
	var n := int(5.5 / DT)
	var pp := PackedVector3Array()
	var pv := PackedVector3Array()
	var pb := PackedByteArray()
	pp.resize(n)
	pv.resize(n)
	pb.resize(n)
	var bc := bounces_since_hit
	pred_has_bounce = false
	pred_first_bounce_t = -1.0
	pred_net = 0
	var count := 0
	for i in n:
		var ev := BallPhysics.step(s, surf, null)
		if ev & BallPhysics.EV_BOUNCE:
			bc += 1
			if not pred_has_bounce:
				pred_has_bounce = true
				pred_first_bounce = s.bounce_pos
				pred_first_bounce_t = clock + (i + 1) * DT
		pred_net |= ev & (BallPhysics.EV_NET | BallPhysics.EV_NET_CORD)
		pp[i] = s.pos
		pv[i] = s.vel
		pb[i] = mini(bc, 255)
		count = i + 1
		if bc - bounces_since_hit >= 3 or s.rolling:
			break
	pp.resize(count)
	pv.resize(count)
	pb.resize(count)
	pred_pos = pp
	pred_vel = pv
	pred_bounces = pb
	pred_t0 = clock
	prediction_changed.emit()


## فهرس عينة التنبؤ الأقرب للزمن المطلق (أو -1)
func pred_index(t_abs: float) -> int:
	var i := int(round((t_abs - pred_t0) / DT)) - 1
	if i < 0 or i >= pred_pos.size():
		return -1
	return i


func pred_time(i: int) -> float:
	return pred_t0 + (i + 1) * DT


func _physics_process(dt: float) -> void:
	# مُراكِم زمني: خطوة المحاكاة ثابتة (1/120 ث) مهما تغيّر مقياس الزمن (للحركة البطيئة لاحقاً)
	_acc += dt
	var guard := 0
	while _acc >= DT - 0.000001 and guard < 16:
		_acc -= DT
		guard += 1
		_tick()
	global_position = st.pos


func _tick() -> void:
	clock += DT
	match mode:
		Mode.HELD:
			if holder != null and holder.has_method("ball_hand_pos"):
				st.pos = holder.ball_hand_pos()
		Mode.FEED:
			var u := clampf((clock - _feed_t0) / _feed_T, 0.0, 1.0)
			var tgt: Vector3 = holder.ball_hand_pos() if holder != null else _feed_target
			var prev := st.pos
			st.pos = _feed_p0.lerp(tgt, u) + Vector3(0, 4.0 * _feed_arc * u * (1.0 - u), 0)
			st.vel = (st.pos - prev) / DT
			if u >= 1.0:
				if holder != null:
					hold(holder)
				else:
					mode = Mode.HELD
					st.vel = Vector3.ZERO
		Mode.TOSS:
			st.pos = toss_pos_at(clock)
			st.vel = _toss_v0 + Vector3(0, -BallPhysics.G * (clock - _toss_t0), 0)
		Mode.FREE:
			var ev := BallPhysics.step(st, surf, rng)
			if ev & (BallPhysics.EV_NET | BallPhysics.EV_NET_CORD):
				net_touched.emit(ev & (BallPhysics.EV_NET | BallPhysics.EV_NET_CORD))
				_predict()
			if ev & BallPhysics.EV_BOUNCE:
				bounces_since_hit += 1
				bounced.emit(st.bounce_pos, st.bounce_speed)
				if float(surf["noise"]) > 0.0 and mode == Mode.FREE:
					_predict()


func _process(dt: float) -> void:
	# دوران الكرة المرئي
	var w := st.spin.length()
	if w > 0.5:
		_spin_basis = Basis(st.spin / w, minf(w, 80.0) * dt) * _spin_basis
		_mesh.basis = _spin_basis.orthonormalized().scaled(Vector3.ONE * _visual_scale)
	# الظل
	var h := maxf(st.pos.y - BallPhysics.R, 0.0)
	var gp := st.pos - sun_dir * (st.pos.y / maxf(sun_dir.y, 0.2))
	gp.y = 0.012
	var size := (0.13 + h * 0.035) * _visual_scale
	_shadow.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(size, 1, size)), gp)
	var sm: ShaderMaterial = _shadow.material_override
	sm.set_shader_parameter("strength", clampf(0.62 - h * 0.05, 0.12, 0.62))
	_shadow.visible = mode != Mode.HELD
	_update_markers(dt, h)
	# أثر السرعة
	var sp := st.vel.length()
	if mode == Mode.FREE and sp > 14.0:
		var ln := clampf(sp * 0.014, 0.1, 0.9)
		var dir := st.vel / sp
		var y := dir
		var x := y.cross(Vector3.UP)
		if x.length_squared() < 0.001:
			x = Vector3.RIGHT
		x = x.normalized()
		var z := x.cross(y)
		_streak.global_transform = Transform3D(Basis(x * _visual_scale, y * ln, z * _visual_scale), st.pos - dir * ln * 0.5)
		_streak.visible = true
	else:
		_streak.visible = false


## مؤشر الأرض: يظهر ما دامت الكرة في الهواء أثناء اللعب، ويقع تحتها مباشرة (إسقاط عمودي لا ظل)،
## وحلقته الداخلية تنكمش مع اقتراب الكرة من الأرض. يختفي بنعومة عند تدحرج الكرة أو انتهاء النقطة.
func _update_markers(dt: float, h: float) -> void:
	_mk_t += dt
	var air := mode == Mode.FREE and in_play and not st.rolling and h > 0.05
	var want := 1.0 if (_marker_mode >= 1 and air) else 0.0
	_marker_a = move_toward(_marker_a, want, dt * (8.0 if want > _marker_a else 4.0))
	_marker.visible = _marker_a > 0.01
	if _marker.visible:
		var k := clampf(0.85 + h * 0.12, 0.85, 1.35) * clampf(_visual_scale / 1.25, 0.8, 1.3)
		_marker.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(k, 1, k)), Vector3(st.pos.x, 0.016, st.pos.z))
		var m: ShaderMaterial = _marker.material_override
		m.set_shader_parameter("alpha", _marker_a * clampf(0.55 + h * 0.6, 0.55, 1.0))
		m.set_shader_parameter("height_k", clampf(h / 2.6, 0.0, 1.0))
		m.set_shader_parameter("pulse", _mk_t * 7.0)
	# مكان السقوط المتوقع: قبل الارتداد الأول فقط
	var want_b := 1.0 if (_marker_mode >= 2 and air and bounces_since_hit == 0 and pred_has_bounce and pred_first_bounce_t > clock) else 0.0
	_bounce_a = move_toward(_bounce_a, want_b, dt * (6.0 if want_b > _bounce_a else 5.0))
	_bounce_mk.visible = _bounce_a > 0.01
	if _bounce_mk.visible:
		_bounce_mk.global_position = Vector3(pred_first_bounce.x, 0.015, pred_first_bounce.z)
		(_bounce_mk.material_override as ShaderMaterial).set_shader_parameter("alpha", _bounce_a)
