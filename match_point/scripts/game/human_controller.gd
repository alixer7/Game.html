class_name HumanController
extends Node
## يربط اللمس باللاعب البشري:
##  - العصا: حركة اللاعب، وأثناء الضغط على زر الضربة تصبح للتصويب (اللاعب يتحرك تلقائياً للكرة)
##  - في الإرسال: العصا تحرك مؤشر مكان الإرسال داخل المربع
##  - شريط التوقيت (QTE) يظهر تلقائياً عند اقتراب الكرة، والإفلات يوقف المؤشر ويحدد جودة الضربة

const SHOTS := [Shot.Type.TOPSPIN, Shot.Type.FLAT, Shot.Type.SLICE, Shot.Type.LOB]
const SERVES := [Shot.Type.SERVE_KICK, Shot.Type.SERVE_FLAT, Shot.Type.SERVE_SLICE]
const QTE_DIST := [10.0, 13.5, 17.0]
const END_LEAD := 0.07
const ZONE_TEXT := {"green": ["ممتاز!", Color(0.35, 1.0, 0.45)], "yellow": ["جيد", Color(1.0, 0.86, 0.25)],
	"red": ["مبكر", Color(1.0, 0.45, 0.35)], "end": ["متأخر!", Color(1.0, 0.3, 0.3)]}

var player: TennisPlayer
var game: TennisMatch
var pad: TouchControls
var bar: QteBar
var marker: MeshInstance3D
var _t := 0.0
var _bar_on := false
var _bar_t0 := 0.0
var _bar_end := 0.0
var _bar_p := 0.0
var _bar_key := "forehand"
var _bar_hide_t := 0.0
var _serve_bar := false
var _pressed := -1


func setup(p: TennisPlayer, g: TennisMatch, p_pad: TouchControls, p_bar: QteBar, parent3d: Node3D) -> void:
	player = p
	game = g
	pad = p_pad
	bar = p_bar
	pad.shot_pressed.connect(_on_pressed)
	pad.shot_aim.connect(_on_drag_aim)
	pad.shot_released.connect(_on_released)
	var q := QuadMesh.new()
	q.size = Vector2(1.15, 1.15)
	q.orientation = PlaneMesh.FACE_Y
	marker = MeshInstance3D.new()
	marker.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/aim_marker.gdshader")
	marker.material_override = m
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	parent3d.add_child(marker)
	game.point_started.connect(func(_s: int, _sec: bool) -> void: _end_bar(true))


func _on_pressed(i: int) -> void:
	_pressed = i
	match player.state:
		TennisPlayer.St.SERVE_READY:
			if i < SERVES.size():
				player.start_serve(SERVES[i])
				_serve_bar = false
		TennisPlayer.St.SERVE_TOSS:
			pass
		_:
			player.begin_prep(SHOTS[i])


var _drag := Vector2.ZERO


func _on_drag_aim(a: Vector2) -> void:
	_drag = a


func _on_released(_i: int) -> void:
	_pressed = -1
	_drag = Vector2.ZERO
	match player.state:
		TennisPlayer.St.SERVE_TOSS:
			# الإفلات بعد رمي الكرة يوقف المؤشر ويضرب. قبل الرمي: ضغطة ثانية لاحقة تضرب
			if player.tossed and not bar.stopped:
				var sp := maxf(player.serve_bar_progress(), 0.0)
				_bar_on = true
				_stop_bar(sp)
				var qa := bar.quality_at(sp)
				player.release_serve(qa[0], qa[1])
		TennisPlayer.St.PREP:
			if _bar_on and not bar.stopped:
				_stop_bar(_bar_p)
				var qa2 := bar.quality_at(_bar_p)
				player.release_shot(qa2[0], qa2[1])
			else:
				# أُفلت قبل اقتراب الكرة: إلغاء التحضير
				player.cancel_prep()
				player.swing_feedback.emit("too_early", 0.0)


func _stop_bar(p: float) -> void:
	var z := bar.zone_at(p)
	if OS.has_environment("MP_QTE"):
		print("QTE stop p=", snappedf(p, 0.01), " zone=", z, " state=", player.state, " t=", snappedf(player.now(), 0.01))
	var zt: Array = ZONE_TEXT[z]
	bar.stop(p, zt[0], zt[1])
	_bar_hide_t = 0.55


func _end_bar(immediate: bool) -> void:
	_bar_on = false
	if immediate:
		bar.hide_bar()
		_bar_hide_t = 0.0


func _stroke_key(c: Dictionary) -> String:
	if int(c["bounces"]) == 0:
		return "volley"
	return "forehand" if float(c["lat"]) >= -0.05 else "backhand"


func _physics_process(dt: float) -> void:
	if player == null:
		return
	_t += dt
	var mv := pad.move
	var st := player.state
	var serving := st == TennisPlayer.St.SERVE_READY or st == TennisPlayer.St.SERVE_TOSS or st == TennisPlayer.St.SERVE_SWING
	if pad.serve_mode != serving:
		pad.serve_mode = serving
		pad.queue_redraw()
	# ---------- العصا ----------
	if serving:
		player.want = Vector3.ZERO
		if st == TennisPlayer.St.SERVE_READY:
			# قبل الضغط على زر الإرسال: العصا تحرك اللاعب على خط القاعدة
			player.want = Vector3(mv.x * player.side, 0.0, 0.0)
		elif st == TennisPlayer.St.SERVE_TOSS and mv.length() > 0.12:
			# بعد الضغط: العصا تحرك مؤشر مكان سقوط الإرسال حتى الإفلات
			var a: Vector2 = player.serve_aim[player.serve_deuce]
			a += Vector2(mv.x, -mv.y) * dt * 2.4
			player.serve_aim[player.serve_deuce] = a.clamp(Vector2(-1, -1), Vector2(1, 1))
	elif st == TennisPlayer.St.PREP:
		var stick := Vector2(mv.x, -mv.y)
		player.aim = stick if stick.length() >= _drag.length() else _drag
		player.want = Vector3.ZERO
	else:
		player.want = Vector3(mv.x * player.side, 0.0, mv.y * player.side)
	pad.charge = player.charge if (st == TennisPlayer.St.PREP or st == TennisPlayer.St.SERVE_TOSS) else 0.0
	pad.ring = -1.0
	# ---------- شريط التوقيت ----------
	_update_bar(dt)
	# ---------- مؤشر التصويب ----------
	var show := false
	if bool(Settings.get_v("aim_marker")):
		if st == TennisPlayer.St.PREP:
			var eff: int = player.prep_type
			if eff == Shot.Type.SLICE and player.aim.y < -0.7:
				eff = Shot.Type.DROP
			marker.position = player.aim_target(eff) + Vector3(0, 0.02, 0)
			show = true
		elif st == TennisPlayer.St.SERVE_TOSS:
			marker.position = player._serve_aim_target() + Vector3(0, 0.02, 0)
			show = true
	marker.visible = show
	if show:
		(marker.material_override as ShaderMaterial).set_shader_parameter("pulse", _t * 8.0)


func _update_bar(dt: float) -> void:
	var st := player.state
	if _bar_hide_t > 0.0:
		_bar_hide_t -= dt
		if _bar_hide_t <= 0.0:
			bar.hide_bar()
			_bar_on = false
		return
	# --- الإرسال: الشريط يتبع رمية الكرة ---
	if st == TennisPlayer.St.SERVE_TOSS:
		var sp := player.serve_bar_progress()
		if sp >= 0.0:
			if not _bar_on:
				_bar_on = true
				bar.start(PlayerProfile.green_width(player.r, "serve_acc") * lerpf(0.65, 1.0, player.stamina))
			_bar_p = sp
			bar.progress = sp
			if sp >= 1.0 and not bar.stopped:
				_stop_bar(1.0)
				player.release_serve(-0.2, 1.0)
		return
	if st == TennisPlayer.St.SERVE_READY or st == TennisPlayer.St.SERVE_SWING:
		if _bar_on:
			_end_bar(true)
		return
	# --- الضربات ---
	var t_now := player.now()
	var c := player.find_contact(0.02, 3.0)
	if c.is_empty():
		if _bar_on and not bar.stopped:
			_end_bar(true)
		return
	var end_t: float = float(c["t"]) - END_LEAD
	if not _bar_on:
		var dist := player.path_to_contact(c)
		if dist <= float(QTE_DIST[clampi(int(Settings.get_v("qte_dist")), 0, 2)]) and end_t - t_now > 0.12:
			_bar_on = true
			_bar_t0 = t_now
			_bar_end = end_t
			_bar_p = 0.0
			_bar_key = _stroke_key(c)
			# التعب يضيّق المنطقة الخضراء
			bar.start(PlayerProfile.green_width(player.r, _bar_key) * lerpf(0.65, 1.0, player.stamina))
			if OS.has_environment("MP_QTE"):
				print("QTE start dist=", snappedf(dist, 0.1), " dur=", snappedf(end_t - t_now, 0.01), " state=", player.state)
		return
	if bar.stopped:
		return
	_bar_end = lerpf(_bar_end, end_t, 0.35)
	var p := (t_now - _bar_t0) / maxf(_bar_end - _bar_t0, 0.05)
	_bar_p = maxf(_bar_p, p)
	bar.progress = _bar_p
	if _bar_p >= 1.0:
		_stop_bar(1.0)
		if st == TennisPlayer.St.PREP:
			player.release_shot(-0.2, 1.0)
		elif player.can_prep() and _ball_worth_playing():
			# لم يُضغط أي زر: محاولة ردّ اضطرارية بأدنى جودة
			player.begin_prep(Shot.Type.TOPSPIN)
			player.charge = 0.3
			player.aim = Vector2.ZERO
			player.release_shot(-0.25, 1.0)


func _ball_worth_playing() -> bool:
	var b := player.ball
	if b.bounces_since_hit >= 1:
		return true
	if b.pred_has_bounce:
		return Court.in_singles(b.pred_first_bounce, player.side) or game.serve_in_flight
	return true
