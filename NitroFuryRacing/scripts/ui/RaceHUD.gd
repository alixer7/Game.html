extends Control

## Bulletproof Mobile-First CTR Race HUD (Safe-Area & LTR-Locked Coordinate Space!).
## Works identically on Arabic RTL and English LTR Android devices across all aspect ratios.

signal pause_pressed()
signal resume_pressed()
signal restart_pressed()
signal respawn_pressed()
signal menu_pressed()
signal next_track_pressed()

var _player: KartPhysics
var _karts: Array[KartPhysics] = []
var _spline: TrackSpline
var _shortcuts: Array = []
var _track_meta: Dictionary = {}

var _lbl_pos: Label
var _lbl_pos_suffix: Label
var _lbl_lap: Label
var _lbl_time: Label
var _lbl_zone: Label
var _lbl_fruit: Label
var _lbl_item: Label
var _item_panel: PanelContainer
var _lbl_banner: Label
var _banner_timer: float = 0.0
var _lbl_wrong_way: Label
var _countdown_box: Control
var _lbl_countdown: Label
var _start_boost_bar: Control

var _minimap: Control
var _boost_gauge: Control
var _speed_lines: Control
var _traffic_lights: Control
var _pause_overlay: Control
var _results_overlay: Control
var _hud_redraw_accum: float = 0.0
var _last_rank: int = -1
var _last_juiced: int = -1
var _last_fruit_count: int = 0
var _fruit_loss_flash: float = 0.0

class SpeedLinesDrawer extends Control:
	var player: KartPhysics
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		if player and is_instance_valid(player) and player.fire_tier >= 3:
			visible = true
			queue_redraw()
		else:
			visible = false

	func _draw() -> void:
		if not player or not is_instance_valid(player) or player.fire_tier < 3:
			return
		var center := size * 0.5
		var max_r := center.length()
		var is_blue := player.fire_tier >= 4
		var col := Color(0.24, 0.94, 1.0, 0.42) if is_blue else Color(1.0, 0.78, 0.18, 0.28)
		var count := 26 if is_blue else 16
		for i in range(count):
			var ang := float(i) / float(count) * TAU + sin(float(i) * 3.7) * 0.08
			var phase := fmod(_t * (4.8 if is_blue else 3.2) + float(i) * 0.37, 1.0)
			var r0 := max_r * lerpf(0.62, 0.94, phase)
			var r1 := max_r * lerpf(0.78, 1.12, phase)
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(center + dir * r0, center + dir * r1, col, 3.2 if is_blue else 2.2, true)

class TrafficLightDrawer extends Control:
	var lit_stage: int = 4

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.09, 0.12, 0.92), true)
		draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.78, 0.16), false, 3.5)
		var rad := h * 0.30
		for i in range(3):
			var cx := w * (0.22 + float(i) * 0.28)
			var cy := h * 0.5
			var bulb := Color(0.20, 0.22, 0.26)
			if lit_stage == 0:
				bulb = Color(0.18, 1.0, 0.32)
			elif lit_stage == 3 and i == 0:
				bulb = Color(1.0, 0.16, 0.12)
			elif lit_stage == 2 and i <= 1:
				bulb = Color(1.0, 0.16, 0.12)
			elif lit_stage == 1:
				bulb = Color(1.0, 0.82, 0.12)
			draw_circle(Vector2(cx, cy), rad + 3.0, Color.BLACK)
			draw_circle(Vector2(cx, cy), rad, bulb)

class StartBoostBarDrawer extends Control:
	## CTR:NF Precision Start-Line Boost Timing Bar (Blue -> Green -> Gold Sweet Spot -> Red Overheat!)
	var player: KartPhysics
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		if visible:
			queue_redraw()

	func _draw() -> void:
		var font := UITheme.font_black()
		var w := size.x
		var h := size.y
		var val := 0.0
		var overheated := false
		if player and is_instance_valid(player):
			val = clampf(player.start_rev_meter, 0.0, 1.0)
			overheated = player.start_rev_overheated

		var in_sweet := (not overheated) and (val >= KartPhysics.START_PERFECT_MIN and val <= KartPhysics.START_PERFECT_MAX)
		var in_good := (not overheated) and (val >= KartPhysics.START_GOOD_MIN and val < KartPhysics.START_PERFECT_MIN)

		# Outer backing card
		draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.07, 0.14, 0.90), true)
		var border_col := Color(1.0, 0.90, 0.14) if in_sweet else (Color(1.0, 0.22, 0.16) if overheated else Color(0.95, 0.72, 0.18, 0.85))
		draw_rect(Rect2(0, 0, w, h), border_col, false, 3.0)

		# Top dynamic guidance prompt
		var hint_txt := GameState.t("start_bar_hint")
		var hint_col := Color(0.86, 0.94, 1.0)
		if overheated:
			hint_txt = GameState.t("start_bar_overheat")
			hint_col = Color(1.0, 0.28, 0.22)
		elif in_sweet:
			hint_txt = GameState.t("start_bar_sweet")
			hint_col = Color(1.0, 0.92, 0.16)
		elif in_good:
			hint_col = Color(0.42, 1.0, 0.48)
		draw_string_outline(font, Vector2(8, 20), hint_txt, HORIZONTAL_ALIGNMENT_CENTER, int(w - 16), 15, 4, Color.BLACK)
		draw_string(font, Vector2(8, 20), hint_txt, HORIZONTAL_ALIGNMENT_CENTER, int(w - 16), 15, hint_col)

		# Precision Timing Bar Zones
		var bar := Rect2(14, 28, w - 28, 26)
		draw_rect(bar, Color(0.10, 0.12, 0.18, 0.96), true)

		var x_good := bar.position.x + bar.size.x * KartPhysics.START_GOOD_MIN
		var x_perf0 := bar.position.x + bar.size.x * KartPhysics.START_PERFECT_MIN
		var x_perf1 := bar.position.x + bar.size.x * KartPhysics.START_PERFECT_MAX

		# Zone 1: Cool Blue (0%..50%)
		draw_rect(Rect2(bar.position.x, bar.position.y, x_good - bar.position.x, bar.size.y), Color(0.14, 0.36, 0.74, 0.36), true)
		# Zone 2: Emerald Green Good Start (50%..76%)
		draw_rect(Rect2(x_good, bar.position.y, x_perf0 - x_good, bar.size.y), Color(0.16, 0.82, 0.36, 0.50), true)
		# Zone 3: Pulsing Golden Sweet Spot (76%..94%)
		var glow := 0.74 + 0.24 * sin(_t * 14.0)
		draw_rect(Rect2(x_perf0, bar.position.y, x_perf1 - x_perf0, bar.size.y), Color(1.0, 0.84, 0.10, glow), true)
		# Zone 4: Overheat Danger Red (94%..100%)
		draw_rect(Rect2(x_perf1, bar.position.y, bar.end.x - x_perf1, bar.size.y), Color(1.0, 0.16, 0.12, 0.78), true)

		# Live fill beam
		if val > 0.005:
			var f_col := Color(0.28, 0.72, 1.0)
			if overheated or val > KartPhysics.START_PERFECT_MAX:
				f_col = Color(1.0, 0.18, 0.14)
			elif val >= KartPhysics.START_PERFECT_MIN:
				f_col = Color(1.0, 0.95, 0.25)
			elif val >= KartPhysics.START_GOOD_MIN:
				f_col = Color(0.28, 1.0, 0.42)
			draw_rect(Rect2(bar.position.x + 1, bar.position.y + 4, (bar.size.x - 2) * val, bar.size.y - 8), f_col, true)

		# Sweet-spot vertical target brackets
		draw_line(Vector2(x_perf0, bar.position.y - 2), Vector2(x_perf0, bar.end.y + 2), Color.WHITE, 2.4)
		draw_line(Vector2(x_perf1, bar.position.y - 2), Vector2(x_perf1, bar.end.y + 2), Color.WHITE, 2.4)

		# Live Crisp Needle Marker
		var nx := bar.position.x + bar.size.x * val
		draw_line(Vector2(nx, bar.position.y - 4), Vector2(nx, bar.end.y + 4), Color.BLACK, 6.5)
		draw_line(Vector2(nx, bar.position.y - 3), Vector2(nx, bar.end.y + 3), Color.WHITE if not overheated else Color(1.0, 0.25, 0.20), 3.4)

		draw_rect(bar, Color.WHITE, false, 2.0)

class MinimapDrawer extends Control:
	var spline: TrackSpline
	var karts: Array[KartPhysics] = []
	var player: KartPhysics
	var shortcuts: Array = []
	var _pts_2d: PackedVector2Array = PackedVector2Array()
	var _bmin: Vector2 = Vector2.ZERO
	var _scale_f: float = 1.0
	var _offset: Vector2 = Vector2.ZERO

	func configure(sp: TrackSpline, ks: Array[KartPhysics], p: KartPhysics, scs: Array) -> void:
		spline = sp
		karts = ks
		player = p
		shortcuts = scs
		_rebuild_poly()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_rebuild_poly()

	func _rebuild_poly() -> void:
		if spline == null or spline.samples.is_empty():
			return
		var sz := size
		if sz.x < 20.0 or sz.y < 20.0:
			sz = custom_minimum_size
		var min_v := Vector2(1e9, 1e9)
		var max_v := Vector2(-1e9, -1e9)
		for s in spline.samples:
			var pos: Vector3 = s["pos"]
			min_v.x = minf(min_v.x, pos.x)
			min_v.y = minf(min_v.y, pos.z)
			max_v.x = maxf(max_v.x, pos.x)
			max_v.y = maxf(max_v.y, pos.z)
		_bmin = min_v
		var span := max_v - min_v
		var draw_area := sz - Vector2(22.0, 22.0)
		_scale_f = minf(draw_area.x / maxf(1.0, span.x), draw_area.y / maxf(1.0, span.y))
		_offset = (sz - span * _scale_f) * 0.5
		_pts_2d.clear()
		for i in range(0, spline.samples.size(), 3):
			var pos: Vector3 = spline.samples[i]["pos"]
			_pts_2d.append(_map_pt(pos))
		if _pts_2d.size() > 0:
			_pts_2d.append(_pts_2d[0])

	func _map_pt(p3: Vector3) -> Vector2:
		return (Vector2(p3.x, p3.z) - _bmin) * _scale_f + _offset

	func _draw() -> void:
		if _pts_2d.size() < 4:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.12, 0.56), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.72, 0.18, 0.70), false, 3.0)
		draw_polyline(_pts_2d, Color(0.08, 0.08, 0.10, 0.9), 7.0, true)
		draw_polyline(_pts_2d, Color(0.92, 0.92, 0.96, 0.88), 3.4, true)

		for sc in shortcuts:
			if GameState.discovered_shortcuts.has(sc["id"]):
				var p0 := _map_pt(sc["launch_tip"])
				var p1 := _map_pt(sc["landing_center"])
				draw_dashed_line(p0, p1, Color(0.18, 0.98, 0.84, 0.92), 3.0, 5.0)

		draw_circle(_pts_2d[0], 4.5, Color(1.0, 0.88, 0.18))

		for k in karts:
			if not is_instance_valid(k) or k == player:
				continue
			var kp := _map_pt(k.global_position)
			var col: Color = k.racer_data.get("body_color", Color.RED)
			draw_circle(kp, 4.6, Color.BLACK)
			draw_circle(kp, 3.4, col)

		if player and is_instance_valid(player):
			var pp := _map_pt(player.global_position)
			draw_circle(pp, 7.0, Color(0.06, 0.04, 0.02))
			draw_circle(pp, 5.2, Color(1.0, 0.88, 0.12))

class BoostGaugeDrawer extends Control:
	var player: KartPhysics
	var _t: float = 0.0
	var _redraw_accum: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		_redraw_accum += delta
		if _redraw_accum >= 0.033:
			_redraw_accum = 0.0
			queue_redraw()

	func _draw() -> void:
		if not player or not is_instance_valid(player):
			return
		var font := UITheme.font_black()
		var w := size.x
		var h := size.y

		var speed_val := player.get_speed_kmh()
		var kmh := "%d" % speed_val
		var tier_col := Color(0.95, 0.95, 0.98)
		var tier_txt := "READY"
		match player.fire_tier:
			1:
				tier_col = Color(1.0, 0.36, 0.12)
				tier_txt = "RED FIRE"
			2:
				tier_col = Color(1.0, 0.72, 0.12)
				tier_txt = "TURBO!"
			3:
				tier_col = Color(1.0, 0.88, 0.16)
				tier_txt = "SACRED FIRE!"
			4:
				tier_col = Color(0.18, 0.94, 1.0)
				tier_txt = "BLUE FIRE!!"

		# Dark stylized rounded-feel dashboard backing
		draw_rect(Rect2(0, 0, w, h), Color(0.06, 0.08, 0.14, 0.78), true)
		var rim_col := tier_col if player.fire_tier >= 3 else Color(1.0, 0.72, 0.20, 0.86)
		draw_rect(Rect2(0, 0, w, h), rim_col, false, 3.0)

		# --- RIGHT SIDE: REFERENCE-MATCHED CURVED ANALOG RAINBOW SPEEDOMETER DIAL! ---
		var dial_c := Vector2(w - 56.0, 64.0)
		var dial_r := 44.0
		var ang_start := deg_to_rad(132.0)
		var ang_span := deg_to_rad(252.0)
		draw_circle(dial_c, dial_r + 3.0, Color(0.04, 0.05, 0.09, 0.92))
		draw_arc(dial_c, dial_r + 3.0, 0.0, TAU, 36, Color(0.90, 0.76, 0.44, 0.85), 2.4, true)
		# Multi-band rainbow arc (Blue -> Cyan -> Emerald -> Gold -> Orange -> Hot Red!)
		var arc_cols: Array[Color] = [
			Color(0.20, 0.48, 1.0),
			Color(0.16, 0.86, 0.98),
			Color(0.24, 0.94, 0.42),
			Color(1.0, 0.86, 0.14),
			Color(1.0, 0.46, 0.08),
			Color(1.0, 0.14, 0.12),
		]
		var seg_n := arc_cols.size()
		for s_i in range(seg_n):
			var a0 := ang_start + ang_span * (float(s_i) / float(seg_n))
			var a1 := ang_start + ang_span * (float(s_i + 1) / float(seg_n))
			draw_arc(dial_c, dial_r - 5.5, a0, a1, 10, arc_cols[s_i], 7.5, true)
		# Crisp dial tick notches
		for t_i in range(9):
			var ta := ang_start + ang_span * (float(t_i) / 8.0)
			var p_in := dial_c + Vector2(cos(ta), sin(ta)) * (dial_r - 14.0)
			var p_out := dial_c + Vector2(cos(ta), sin(ta)) * (dial_r - 9.0)
			draw_line(p_in, p_out, Color(0.96, 0.96, 1.0, 0.85), 1.8, true)
		# Live Sweeping Glowing Orange Speedometer Needle!
		var spd_frac := clampf(float(speed_val) / 225.0, 0.0, 1.0)
		var needle_ang := ang_start + ang_span * spd_frac
		var needle_tip := dial_c + Vector2(cos(needle_ang), sin(needle_ang)) * (dial_r - 6.0)
		var needle_tail := dial_c - Vector2(cos(needle_ang), sin(needle_ang)) * 9.0
		draw_line(needle_tail, needle_tip, Color(1.0, 0.56, 0.10), 4.2, true)
		draw_line(needle_tail, needle_tip, Color(1.0, 0.92, 0.55), 1.8, true)
		draw_circle(dial_c, 6.2, Color(0.86, 0.68, 0.30))
		draw_circle(dial_c, 3.2, Color(0.10, 0.12, 0.16))
		# Digital KM/H readout nested cleanly at bottom of analog dial!
		draw_string_outline(font, Vector2(dial_c.x - 22.0, dial_c.y + 30.0), kmh, HORIZONTAL_ALIGNMENT_CENTER, 44, 18, 4, Color.BLACK)
		draw_string(font, Vector2(dial_c.x - 22.0, dial_c.y + 30.0), kmh, HORIZONTAL_ALIGNMENT_CENTER, 44, 18, tier_col)
		draw_string(font, Vector2(dial_c.x - 20.0, dial_c.y + 42.0), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color(0.82, 0.88, 0.96))

		# --- LEFT SIDE: FIRE TIER + DRIFT POWER-SLIDE BAR + RESERVES ---
		var left_w := w - 114.0
		var pulse := 1.0 if player.fire_tier < 4 else (0.76 + 0.24 * sin(_t * 18.0))
		var tc := tier_col * Color(1, 1, 1, pulse)
		draw_string_outline(font, Vector2(10, 26), tier_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		draw_string(font, Vector2(10, 26), tier_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tc)

		# 3-Boost Drift Stage Pips
		for p_idx in range(3):
			var px := 18.0 + float(p_idx) * 18.0
			var lit := player.is_drifting and (p_idx < player.drift_boost_count)
			draw_circle(Vector2(px, 42), 5.5, Color(1.0, 0.88, 0.12) if lit else Color(0.24, 0.26, 0.32))
			draw_arc(Vector2(px, 42), 5.5, 0, TAU, 12, Color.BLACK, 1.8)

		var bar_rect := Rect2(10, 54, left_w, 18)
		draw_rect(bar_rect, Color(0.12, 0.12, 0.16, 0.92), true)
		var good_x := bar_rect.position.x + bar_rect.size.x * 0.48
		var perf_x := bar_rect.position.x + bar_rect.size.x * 0.76
		draw_rect(Rect2(good_x, bar_rect.position.y, perf_x - good_x, bar_rect.size.y), Color(0.18, 0.70, 0.24, 0.34), true)
		draw_rect(Rect2(perf_x, bar_rect.position.y, bar_rect.end.x - perf_x, bar_rect.size.y), Color(1.0, 0.22, 0.08, 0.44), true)

		if player.is_drifting:
			var fill_w := clampf(player.drift_charge, 0.0, 1.0) * bar_rect.size.x
			var f_col := Color(1.0, 0.75, 0.15)
			if player.drift_charge >= 0.76:
				f_col = Color(1.0, 0.18, 0.08)
			elif player.drift_charge >= 0.48:
				f_col = Color(0.24, 0.96, 0.34)
			draw_rect(Rect2(bar_rect.position.x, bar_rect.position.y + 2, fill_w, bar_rect.size.y - 4), f_col, true)
		draw_rect(bar_rect, Color.WHITE, false, 1.8)

		if GameState.show_ctr_telemetry:
			var res_rect := Rect2(10, 80, left_w, 12)
			draw_rect(res_rect, Color(0.08, 0.08, 0.12, 0.9), true)
			var res_frac := clampf(player.reserves / 8.0, 0.0, 1.0)
			if res_frac > 0.001:
				draw_rect(Rect2(res_rect.position.x, res_rect.position.y + 1, res_frac * res_rect.size.x, res_rect.size.y - 2), tier_col, true)
			draw_rect(res_rect, Color(0.7, 0.75, 0.85, 0.75), false, 1.4)
			var res_lbl := "%.1fs" % player.reserves
			draw_string_outline(font, Vector2(10, 110), GameState.t("reserves") + " " + res_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			draw_string(font, Vector2(10, 110), GameState.t("reserves") + " " + res_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.86, 0.92, 1.0))

func setup(player: KartPhysics, karts: Array[KartPhysics], spline: TrackSpline, shortcuts: Array, track_meta: Dictionary) -> void:
	_player = player
	_karts = karts
	_spline = spline
	_shortcuts = shortcuts
	_track_meta = track_meta
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _get_safe_margins() -> Dictionary:
	var vp := get_viewport().get_visible_rect().size
	var l := 22
	var r := 22
	var t := 14
	var b := 14
	var win_sz := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win_sz.x > 0 and win_sz.y > 0 and safe.size.x > 0 and safe.size.y > 0:
		var sx := vp.x / float(win_sz.x)
		var sy := vp.y / float(win_sz.y)
		l = maxi(l, int(ceilf(float(safe.position.x) * sx)) + 12)
		r = maxi(r, int(ceilf(float(win_sz.x - safe.end.x) * sx)) + 12)
		t = maxi(t, int(ceilf(float(safe.position.y) * sy)) + 10)
		b = maxi(b, int(ceilf(float(win_sz.y - safe.end.y) * sy)) + 10)
	return {"left": l, "right": r, "top": t, "bottom": b}

func _build_ui() -> void:
	# Full-screen radial Blue/Sacred Fire speed lines
	_speed_lines = SpeedLinesDrawer.new()
	_speed_lines.player = _player
	_speed_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_lines.visible = false
	add_child(_speed_lines)

	# Responsive Safe-Area HUD Container (LTR locked — NEVER mirrors on Arabic OS!)
	var mc := MarginContainer.new()
	mc.layout_direction = Control.LAYOUT_DIRECTION_LTR
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := _get_safe_margins()
	mc.add_theme_constant_override("margin_left", sm["left"])
	mc.add_theme_constant_override("margin_right", sm["right"])
	mc.add_theme_constant_override("margin_top", sm["top"])
	mc.add_theme_constant_override("margin_bottom", sm["bottom"])
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mc)

	var top_split := HBoxContainer.new()
	top_split.layout_direction = Control.LAYOUT_DIRECTION_LTR
	top_split.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(top_split)

	# --- LEFT HUD COLUMN: Position/Lap/Timer + Minimap ---
	var left_v := VBoxContainer.new()
	left_v.layout_direction = Control.LAYOUT_DIRECTION_LTR
	left_v.add_theme_constant_override("separation", 8)
	left_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_split.add_child(left_v)

	var tl_panel := PanelContainer.new()
	tl_panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.08, 0.10, 0.18, 0.80), Color(1.0, 0.68, 0.12), 14, 3, 4))
	tl_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_v.add_child(tl_panel)

	var tl_h := HBoxContainer.new()
	tl_h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	tl_h.add_theme_constant_override("separation", 12)
	tl_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl_panel.add_child(tl_h)

	var pos_box := HBoxContainer.new()
	pos_box.layout_direction = Control.LAYOUT_DIRECTION_LTR
	pos_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_pos = UITheme.make_label("1", 42, Color(1.0, 0.86, 0.14), HORIZONTAL_ALIGNMENT_LEFT, 7)
	_lbl_pos_suffix = UITheme.make_label("ST", 18, Color(1.0, 0.92, 0.55), HORIZONTAL_ALIGNMENT_LEFT, 5)
	pos_box.add_child(_lbl_pos)
	pos_box.add_child(_lbl_pos_suffix)
	tl_h.add_child(pos_box)

	var info_v := VBoxContainer.new()
	info_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_lap = UITheme.make_label("LAP 1/3", 19, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 5)
	_lbl_time = UITheme.make_label("00:00.00", 17, Color(0.75, 0.94, 1.0), HORIZONTAL_ALIGNMENT_LEFT, 4)
	_lbl_zone = UITheme.make_label("", 12, Color(1.0, 0.82, 0.45), HORIZONTAL_ALIGNMENT_LEFT, 3)
	info_v.add_child(_lbl_lap)
	info_v.add_child(_lbl_time)
	info_v.add_child(_lbl_zone)
	tl_h.add_child(info_v)

	_minimap = MinimapDrawer.new()
	_minimap.custom_minimum_size = Vector2(158, 136)
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_v.add_child(_minimap)
	_minimap.configure(_spline, _karts, _player, _shortcuts)

	# --- CENTER SPACER + EVENT BANNER ---
	var center_v := VBoxContainer.new()
	center_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_v.add_theme_constant_override("separation", 6)
	center_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_split.add_child(center_v)

	_lbl_banner = UITheme.make_label("", 30, Color(1.0, 0.88, 0.14), HORIZONTAL_ALIGNMENT_CENTER, 7)
	_lbl_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_v.add_child(_lbl_banner)

	_lbl_wrong_way = UITheme.make_label(GameState.t("wrong_way"), 34, Color(1.0, 0.18, 0.12), HORIZONTAL_ALIGNMENT_CENTER, 7)
	_lbl_wrong_way.visible = false
	_lbl_wrong_way.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_v.add_child(_lbl_wrong_way)

	# --- RIGHT HUD COLUMN: Item + Fruits + Respawn/Reset + Pause + Boost/Speedometer Gauge ---
	var right_v := VBoxContainer.new()
	right_v.layout_direction = Control.LAYOUT_DIRECTION_LTR
	right_v.add_theme_constant_override("separation", 8)
	right_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_split.add_child(right_v)

	var tr_h := HBoxContainer.new()
	tr_h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	tr_h.alignment = BoxContainer.ALIGNMENT_END
	tr_h.add_theme_constant_override("separation", 8)
	tr_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_v.add_child(tr_h)

	_item_panel = PanelContainer.new()
	_item_panel.custom_minimum_size = Vector2(104, 60)
	_item_panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.14, 0.08, 0.24, 0.84), Color(0.95, 0.72, 0.12), 14, 3, 4))
	_item_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_item = UITheme.make_label("--", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 4)
	_item_panel.add_child(_lbl_item)
	tr_h.add_child(_item_panel)

	var fruit_panel := PanelContainer.new()
	fruit_panel.custom_minimum_size = Vector2(114, 60)
	fruit_panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.24, 0.12, 0.04, 0.84), Color(1.0, 0.72, 0.10), 14, 3, 4))
	fruit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_fruit = UITheme.make_label("0 / 10", 19, Color(1.0, 0.86, 0.16), HORIZONTAL_ALIGNMENT_CENTER, 5)
	fruit_panel.add_child(_lbl_fruit)
	tr_h.add_child(fruit_panel)

	# Instant Unstuck / Respawn to Track Button (crisp localized label!)
	var respawn_btn := Button.new()
	respawn_btn.text = GameState.t("btn_rescue")
	respawn_btn.custom_minimum_size = Vector2(78, 58)
	UITheme.style_button(respawn_btn, Color(0.16, 0.52, 0.84), Color.WHITE, 17, 14)
	respawn_btn.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("ui_click")
		respawn_pressed.emit()
	)
	tr_h.add_child(respawn_btn)

	# Quick Restart in Time Trial / Practice Mode
	if GameState.selected_mode == GameState.GameMode.TIME_TRIAL or GameState.selected_mode == GameState.GameMode.PRACTICE_ACADEMY:
		var q_res := Button.new()
		q_res.text = GameState.t("btn_retry")
		q_res.custom_minimum_size = Vector2(82, 58)
		UITheme.style_button(q_res, Color(0.90, 0.52, 0.08), Color.WHITE, 17, 14)
		q_res.pressed.connect(func():
			if AudioSynth: AudioSynth.play_sfx("ui_click")
			restart_pressed.emit()
		)
		tr_h.add_child(q_res)

	var pause_btn := Button.new()
	pause_btn.text = "||"
	pause_btn.custom_minimum_size = Vector2(60, 58)
	UITheme.style_button(pause_btn, Color(0.86, 0.26, 0.10), Color.WHITE, 22, 14)
	pause_btn.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("ui_click")
		pause_pressed.emit()
	)
	tr_h.add_child(pause_btn)

	# Speedometer + Boost Meter + Reserves Gauge right-aligned directly below top-right bar
	var gauge_align := HBoxContainer.new()
	gauge_align.layout_direction = Control.LAYOUT_DIRECTION_LTR
	gauge_align.alignment = BoxContainer.ALIGNMENT_END
	gauge_align.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_v.add_child(gauge_align)

	_boost_gauge = BoostGaugeDrawer.new()
	_boost_gauge.player = _player
	_boost_gauge.custom_minimum_size = Vector2(230, 124)
	_boost_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge_align.add_child(_boost_gauge)

	# --- CENTER: 3-2-1-GO COUNTDOWN + TRAFFIC LIGHTS + START REV BAR ---
	var cd_center := CenterContainer.new()
	cd_center.layout_direction = Control.LAYOUT_DIRECTION_LTR
	cd_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cd_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cd_center)

	_countdown_box = VBoxContainer.new()
	_countdown_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_countdown_box.add_theme_constant_override("separation", 6)
	_countdown_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_center.add_child(_countdown_box)

	var light_center := CenterContainer.new()
	light_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_traffic_lights = TrafficLightDrawer.new()
	_traffic_lights.custom_minimum_size = Vector2(210, 62)
	_traffic_lights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	light_center.add_child(_traffic_lights)
	_countdown_box.add_child(light_center)

	_lbl_countdown = UITheme.make_label("READY!", 68, Color(1.0, 0.86, 0.14), HORIZONTAL_ALIGNMENT_CENTER, 10)
	_countdown_box.add_child(_lbl_countdown)

	var bar_center := CenterContainer.new()
	bar_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_boost_bar = StartBoostBarDrawer.new()
	_start_boost_bar.player = _player
	_start_boost_bar.custom_minimum_size = Vector2(400, 64)
	_start_boost_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_center.add_child(_start_boost_bar)
	_countdown_box.add_child(bar_center)

	_build_pause_overlay()
	_build_results_overlay()

func _build_pause_overlay() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.color = Color(0.02, 0.04, 0.08, 0.74)
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 460)
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.10, 0.14, 0.24, 0.96), Color(1.0, 0.70, 0.14), 22, 5, 10))
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)

	v.add_child(UITheme.make_label(GameState.t("paused"), 34, Color(1.0, 0.85, 0.14), HORIZONTAL_ALIGNMENT_CENTER, 7))

	var btn_resume := Button.new()
	btn_resume.text = GameState.t("resume")
	btn_resume.custom_minimum_size = Vector2(0, 56)
	UITheme.style_button(btn_resume, Color(0.16, 0.74, 0.28), Color.WHITE, 23)
	btn_resume.pressed.connect(func(): resume_pressed.emit())
	v.add_child(btn_resume)

	var row1 := HBoxContainer.new()
	row1.layout_direction = Control.LAYOUT_DIRECTION_LTR
	row1.add_theme_constant_override("separation", 10)
	v.add_child(row1)

	var btn_restart := Button.new()
	btn_restart.text = GameState.t("restart")
	btn_restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_restart.custom_minimum_size = Vector2(0, 52)
	UITheme.style_button(btn_restart, Color(0.92, 0.52, 0.08), Color.WHITE, 19)
	btn_restart.pressed.connect(func(): restart_pressed.emit())
	row1.add_child(btn_restart)

	var btn_resp := Button.new()
	btn_resp.text = GameState.t("respawn_track")
	btn_resp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_resp.custom_minimum_size = Vector2(0, 52)
	UITheme.style_button(btn_resp, Color(0.14, 0.56, 0.86), Color.WHITE, 19)
	btn_resp.pressed.connect(func():
		resume_pressed.emit()
		respawn_pressed.emit()
	)
	row1.add_child(btn_resp)

	# Live mobile control settings grid inside Pause!
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)

	var btn_steer := Button.new()
	btn_steer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_steer.custom_minimum_size = Vector2(0, 48)
	btn_steer.text = "%s: %s" % [GameState.t("steer_mode"), GameState.t("steer_stick") if GameState.use_joystick else GameState.t("steer_buttons")]
	UITheme.style_button(btn_steer, Color(0.18, 0.44, 0.78), Color.WHITE, 15)
	btn_steer.pressed.connect(func():
		GameState.use_joystick = not GameState.use_joystick
		GameState.save_data()
		btn_steer.text = "%s: %s" % [GameState.t("steer_mode"), GameState.t("steer_stick") if GameState.use_joystick else GameState.t("steer_buttons")]
	)
	grid.add_child(btn_steer)

	var btn_gas := Button.new()
	btn_gas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_gas.custom_minimum_size = Vector2(0, 48)
	btn_gas.text = "%s: %s" % [GameState.t("auto_gas"), GameState.t("on") if GameState.auto_accelerate else GameState.t("off")]
	UITheme.style_button(btn_gas, Color(0.24, 0.38, 0.68), Color.WHITE, 15)
	btn_gas.pressed.connect(func():
		GameState.auto_accelerate = not GameState.auto_accelerate
		GameState.save_data()
		btn_gas.text = "%s: %s" % [GameState.t("auto_gas"), GameState.t("on") if GameState.auto_accelerate else GameState.t("off")]
	)
	grid.add_child(btn_gas)

	var btn_tel := Button.new()
	btn_tel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tel.custom_minimum_size = Vector2(0, 48)
	btn_tel.text = "%s: %s" % [GameState.t("telemetry"), GameState.t("on") if GameState.show_ctr_telemetry else GameState.t("off")]
	UITheme.style_button(btn_tel, Color(0.48, 0.30, 0.72), Color.WHITE, 15)
	btn_tel.pressed.connect(func():
		GameState.show_ctr_telemetry = not GameState.show_ctr_telemetry
		GameState.save_data()
		btn_tel.text = "%s: %s" % [GameState.t("telemetry"), GameState.t("on") if GameState.show_ctr_telemetry else GameState.t("off")]
	)
	grid.add_child(btn_tel)

	var btn_mute := Button.new()
	btn_mute.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_mute.custom_minimum_size = Vector2(0, 48)
	btn_mute.text = "%s: %d%%" % [GameState.t("sfx_vol"), int(round(GameState.sfx_volume * 100.0))]
	UITheme.style_button(btn_mute, Color(0.36, 0.30, 0.64), Color.WHITE, 15)
	btn_mute.pressed.connect(func():
		GameState.sfx_volume = 0.0 if GameState.sfx_volume > 0.1 else 0.85
		GameState.music_volume = 0.0 if GameState.sfx_volume <= 0.1 else 0.55
		GameState.save_data()
		GameState.settings_changed.emit()
		btn_mute.text = "%s: %d%%" % [GameState.t("sfx_vol"), int(round(GameState.sfx_volume * 100.0))]
	)
	grid.add_child(btn_mute)

	var btn_menu := Button.new()
	btn_menu.text = GameState.t("main_menu")
	btn_menu.custom_minimum_size = Vector2(0, 52)
	UITheme.style_button(btn_menu, Color(0.76, 0.16, 0.16), Color.WHITE, 21)
	btn_menu.pressed.connect(func(): menu_pressed.emit())
	v.add_child(btn_menu)

func _build_results_overlay() -> void:
	_results_overlay = ColorRect.new()
	_results_overlay.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_results_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_overlay.color = Color(0.03, 0.05, 0.10, 0.82)
	_results_overlay.visible = false
	add_child(_results_overlay)

func set_countdown(stage: int) -> void:
	if _traffic_lights:
		_traffic_lights.lit_stage = stage
		_traffic_lights.queue_redraw()
	if stage > 0:
		_countdown_box.visible = true
		_lbl_countdown.text = str(stage)
		_lbl_countdown.add_theme_color_override("font_color", Color(1.0, 0.24, 0.14) if stage == 3 else (Color(1.0, 0.72, 0.12) if stage == 2 else Color(0.98, 0.96, 0.22)))
	else:
		_lbl_countdown.text = "GO!!"
		_lbl_countdown.add_theme_color_override("font_color", Color(0.24, 1.0, 0.36))
		if _start_boost_bar:
			_start_boost_bar.visible = false
		get_tree().create_timer(0.85).timeout.connect(func():
			if is_instance_valid(_countdown_box):
				_countdown_box.visible = false
		)

func show_banner(txt: String, col: Color) -> void:
	_lbl_banner.text = txt
	_lbl_banner.add_theme_color_override("font_color", col)
	_banner_timer = 1.65

func set_paused(p: bool) -> void:
	_pause_overlay.visible = p

func _set_txt(lbl: Label, txt: String) -> void:
	if lbl and lbl.text != txt:
		lbl.text = txt

func update_hud(rank: int, total_karts: int) -> void:
	if not _player or not is_instance_valid(_player):
		return
	var dt := get_process_delta_time()
	if _banner_timer > 0.0:
		_banner_timer -= dt
		if _banner_timer <= 0.0:
			_set_txt(_lbl_banner, "")

	if not _player.race_started and _start_boost_bar:
		_start_boost_bar.visible = true

	if rank != _last_rank:
		_last_rank = rank
		_set_txt(_lbl_pos, str(rank))
		var suf := "ST" if rank == 1 else ("ND" if rank == 2 else ("RD" if rank == 3 else "TH"))
		_set_txt(_lbl_pos_suffix, "%s / %d" % [suf, total_karts])
		var pcol := Color(1.0, 0.86, 0.14) if rank == 1 else (Color(0.85, 0.90, 0.98) if rank == 2 else (Color(0.92, 0.56, 0.26) if rank == 3 else Color.WHITE))
		_lbl_pos.add_theme_color_override("font_color", pcol)

	var lap_disp := "%s %d/%d" % [GameState.t("lap"), mini(_player.current_lap, _player.total_laps), _player.total_laps]
	if _player.total_laps > 20:
		lap_disp = "%s %d" % [GameState.t("lap"), _player.current_lap]
	_set_txt(_lbl_lap, lap_disp)

	if _player.fruit_count < _last_fruit_count:
		_fruit_loss_flash = 0.65
	_last_fruit_count = _player.fruit_count
	if _fruit_loss_flash > 0.0:
		_fruit_loss_flash = maxf(0.0, _fruit_loss_flash - dt)

	var juiced_i := 1 if _player.is_juiced() else 0
	var fruit_txt := ("%d/10 %s" % [_player.fruit_count, GameState.t("juiced")]) if juiced_i == 1 else ("%d / 10" % _player.fruit_count)
	_set_txt(_lbl_fruit, fruit_txt)
	if _fruit_loss_flash > 0.0:
		_lbl_fruit.add_theme_color_override("font_color", Color(1.0, 0.22, 0.18))
		_last_juiced = -1
	elif juiced_i != _last_juiced:
		_last_juiced = juiced_i
		_lbl_fruit.add_theme_color_override("font_color", Color(1.0, 0.95, 0.22) if juiced_i == 1 else Color(1.0, 0.72, 0.24))

	if _player.item_roulette_timer > 0.0:
		var keys := ["item_turbo", "item_missile", "item_bomb", "item_shield", "item_tnt", "item_mask"]
		_set_txt(_lbl_item, GameState.t(keys[int(Time.get_ticks_msec() / 70) % keys.size()]))
	elif _player.held_item != "":
		_set_txt(_lbl_item, GameState.t("item_" + _player.held_item))
	else:
		_set_txt(_lbl_item, "--")

	_lbl_wrong_way.visible = _player.wrong_way and _player.race_started

	# Throttle high-frequency timer/zone/minimap updates cleanly to 30Hz (eliminates HarfBuzz & Canvas spikes on mobile!)
	_hud_redraw_accum += dt
	if _hud_redraw_accum >= 0.033:
		_hud_redraw_accum = 0.0
		_set_txt(_lbl_time, GameState.format_time(_player.race_elapsed))
		if _spline != null:
			var s := _spline.sample_at_t(_player.spline_t)
			_set_txt(_lbl_zone, str(s.get("zone", "")))
		if _minimap:
			_minimap.queue_redraw()

func show_results(res: Dictionary) -> void:
	for c in _results_overlay.get_children():
		c.queue_free()
	_results_overlay.visible = true

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 500)
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.08, 0.11, 0.20, 0.96), Color(1.0, 0.76, 0.14), 24, 5, 12))
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var rank: int = int(res["rank"])
	var headline := "#%d  %s" % [rank, GameState.t("race_finish")]
	if bool(res["is_gp"]) and not bool(res["gp_has_next"]) and GameState.gp_standings.size() > 0 and GameState.gp_standings[0]["is_player"]:
		headline = GameState.t("cup_champion")
	v.add_child(UITheme.make_label(headline, 36, Color(1.0, 0.86, 0.16), HORIZONTAL_ALIGNMENT_CENTER, 8))

	var stats_line := "%s  |  %s: %s" % [
		GameState.format_time(float(res["total_time"])),
		GameState.t("best_time"),
		GameState.format_time(float(res["best_lap"]))
	]
	if str(res.get("medal", "")) != "":
		stats_line += "  |  %s MEDAL" % str(res["medal"])
	if bool(res.get("new_record", false)):
		stats_line += "  ★ " + GameState.t("new_record")
	v.add_child(UITheme.make_label(stats_line, 18, Color(0.45, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 4))

	if int(res.get("shortcuts", 0)) > 0:
		v.add_child(UITheme.make_label("%s: %d" % [GameState.t("shortcut_found"), int(res["shortcuts"])], 18, Color(0.32, 1.0, 0.65), HORIZONTAL_ALIGNMENT_CENTER, 4))

	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 6)
	v.add_child(list_box)

	if bool(res["is_gp"]):
		list_box.add_child(UITheme.make_label(GameState.t("gp_standings"), 20, Color(1.0, 0.78, 0.28), HORIZONTAL_ALIGNMENT_CENTER, 4))
		for idx in range(GameState.gp_standings.size()):
			var s: Dictionary = GameState.gp_standings[idx]
			var col := Color(1.0, 0.92, 0.25) if bool(s["is_player"]) else Color(0.92, 0.94, 0.98)
			var row_txt := "%d.  %s   —   %d %s" % [idx + 1, GameState.get_racer_name(s["racer"]), int(s["points"]), GameState.t("pts")]
			list_box.add_child(UITheme.make_label(row_txt, 19, col, HORIZONTAL_ALIGNMENT_CENTER, 4))
	else:
		var fl: Array = res["finish_list"]
		for idx in range(fl.size()):
			var e: Dictionary = fl[idx]
			var col := Color(1.0, 0.92, 0.25) if bool(e["is_player"]) else Color(0.92, 0.94, 0.98)
			var row_txt := "%d.  %s   —   %s" % [idx + 1, str(e["name"]), GameState.format_time(float(e["time"]))]
			list_box.add_child(UITheme.make_label(row_txt, 19, col, HORIZONTAL_ALIGNMENT_CENTER, 4))

	var btns := HBoxContainer.new()
	btns.layout_direction = Control.LAYOUT_DIRECTION_LTR
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 18)
	v.add_child(btns)

	if bool(res.get("gp_has_next", false)):
		var b_next := Button.new()
		b_next.text = GameState.t("next_track")
		UITheme.style_button(b_next, Color(0.14, 0.78, 0.30), Color.WHITE, 23)
		b_next.pressed.connect(func(): next_track_pressed.emit())
		btns.add_child(b_next)
	else:
		var b_again := Button.new()
		b_again.text = GameState.t("restart")
		UITheme.style_button(b_again, Color(0.96, 0.50, 0.08), Color.WHITE, 21)
		b_again.pressed.connect(func(): restart_pressed.emit())
		btns.add_child(b_again)

	var b_menu := Button.new()
	b_menu.text = GameState.t("main_menu")
	UITheme.style_button(b_menu, Color(0.20, 0.44, 0.82), Color.WHITE, 21)
	b_menu.pressed.connect(func(): menu_pressed.emit())
	btns.add_child(b_menu)
