class_name Hud
extends Control
## In-match overlay: scoreboard, clock, centre messages, event feed,
## points popups and an off-screen ball indicator.

var score_box: HBoxContainer
var blue_lbl: Label
var orange_lbl: Label
var time_lbl: Label
var ot_lbl: Label
var big_lbl: Label
var sub_lbl: Label
var feed: VBoxContainer
var popup_lbl: Label
var replay_banner: PanelContainer
var replay_hint: Label
var fps_lbl: Label
var camera: Camera3D
var ball_pos := Vector3.ZERO
var show_ball_indicator := true
var _big_tween: Tween
var _popup_tween: Tween
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.theme()
	_font = UiTheme.font_black()

	# --- scoreboard
	var top := CenterContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 10
	top.offset_bottom = 90
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	score_box = HBoxContainer.new()
	score_box.add_theme_constant_override("separation", 0)
	score_box.layout_direction = Control.LAYOUT_DIRECTION_LTR
	top.add_child(score_box)
	blue_lbl = _score_panel(score_box, UiTheme.BLUE, true)
	var mid := PanelContainer.new()
	var sb := UiTheme.box(Color(0.03, 0.04, 0.08, 0.9), 0)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	mid.add_theme_stylebox_override("panel", sb)
	var mid_v := VBoxContainer.new()
	mid_v.add_theme_constant_override("separation", -10)
	mid.add_child(mid_v)
	time_lbl = UiTheme.label("5:00", 40, Color.WHITE, true)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_lbl.custom_minimum_size = Vector2(120, 0)
	mid_v.add_child(time_lbl)
	ot_lbl = UiTheme.label("", 16, Color(1, 0.85, 0.3), false)
	ot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_v.add_child(ot_lbl)
	score_box.add_child(mid)
	orange_lbl = _score_panel(score_box, UiTheme.ORANGE, false)

	# --- centre message
	big_lbl = UiTheme.label("", 110, Color.WHITE, true)
	big_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_lbl.add_theme_constant_override("outline_size", 18)
	big_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	big_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	big_lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
	big_lbl.offset_left = -600
	big_lbl.offset_right = 600
	big_lbl.offset_top = -170
	big_lbl.offset_bottom = 10
	big_lbl.pivot_offset = Vector2(600, 90)
	big_lbl.modulate.a = 0.0
	add_child(big_lbl)
	sub_lbl = UiTheme.label("", 34, Color(0.92, 0.95, 1.0), false)
	sub_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub_lbl.offset_left = -600
	sub_lbl.offset_right = 600
	sub_lbl.offset_top = 10
	sub_lbl.offset_bottom = 60
	sub_lbl.add_theme_constant_override("outline_size", 10)
	sub_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	sub_lbl.modulate.a = 0.0
	add_child(sub_lbl)

	# --- feed (top right)
	feed = VBoxContainer.new()
	feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed.offset_left = -420
	feed.offset_right = -20
	feed.offset_top = 100
	feed.offset_bottom = 300
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed)

	# --- points popup
	popup_lbl = UiTheme.label("", 36, Color(1, 0.9, 0.45), true)
	popup_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	popup_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup_lbl.offset_left = -400
	popup_lbl.offset_right = 400
	popup_lbl.offset_top = -250
	popup_lbl.offset_bottom = -200
	popup_lbl.add_theme_constant_override("outline_size", 10)
	popup_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	popup_lbl.modulate.a = 0.0
	add_child(popup_lbl)

	# --- replay banner
	replay_banner = PanelContainer.new()
	replay_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	replay_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	replay_banner.offset_top = 128
	replay_banner.offset_left = -160
	replay_banner.offset_right = 160
	replay_banner.add_theme_stylebox_override("panel", UiTheme.box(Color(0.85, 0.12, 0.2, 0.9), 10))
	var rv := VBoxContainer.new()
	replay_banner.add_child(rv)
	var rl := UiTheme.label(Loc.t("replay"), 32, Color.WHITE, true)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rl)
	replay_hint = UiTheme.label(Loc.t("tap_skip"), 18, Color(1, 1, 1, 0.8))
	replay_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(replay_hint)
	replay_banner.visible = false
	add_child(replay_banner)

	fps_lbl = UiTheme.label("", 18, Color(0.7, 1, 0.7))
	fps_lbl.position = Vector2(110, 30)
	add_child(fps_lbl)


func _score_panel(parent: Control, col: Color, left: bool) -> Label:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.75, col.g * 0.75, col.b * 0.75, 0.92)
	if left:
		sb.corner_radius_top_left = 16
		sb.corner_radius_bottom_left = 16
	else:
		sb.corner_radius_top_right = 16
		sb.corner_radius_bottom_right = 16
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.border_color = col.lightened(0.3)
	sb.border_width_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var l := UiTheme.label("0", 46, Color.WHITE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(64, 0)
	p.add_child(l)
	parent.add_child(p)
	return l


func set_scores(blue: int, orange: int) -> void:
	if blue_lbl.text != str(blue):
		_bump(blue_lbl)
	if orange_lbl.text != str(orange):
		_bump(orange_lbl)
	blue_lbl.text = str(blue)
	orange_lbl.text = str(orange)


func _bump(l: Label) -> void:
	l.pivot_offset = l.size * 0.5
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.5, 1.5), 0.12)
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


func set_time(seconds: float, overtime: bool, unlimited: bool = false) -> void:
	if unlimited:
		time_lbl.text = "∞"
		ot_lbl.text = ""
		return
	var s := int(ceil(seconds)) if not overtime else int(floor(seconds))
	time_lbl.text = "%d:%02d" % [s / 60, s % 60]
	ot_lbl.text = Loc.t("overtime") if overtime else ""
	time_lbl.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if (not overtime and seconds <= 30.0 and seconds > 0.0) else Color.WHITE)


func show_big(text: String, sub: String = "", color: Color = Color.WHITE, dur: float = 1.6, punch: bool = true) -> void:
	big_lbl.text = text
	big_lbl.add_theme_color_override("font_color", color)
	sub_lbl.text = sub
	if _big_tween:
		_big_tween.kill()
	big_lbl.modulate.a = 1.0
	sub_lbl.modulate.a = 1.0 if sub != "" else 0.0
	big_lbl.scale = Vector2(1.8, 1.8) if punch else Vector2.ONE
	_big_tween = create_tween()
	_big_tween.tween_property(big_lbl, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if dur > 0.0:
		_big_tween.tween_interval(dur)
		_big_tween.set_parallel(true)
		_big_tween.tween_property(big_lbl, "modulate:a", 0.0, 0.35)
		_big_tween.tween_property(sub_lbl, "modulate:a", 0.0, 0.35)


func hide_big() -> void:
	if _big_tween:
		_big_tween.kill()
	big_lbl.modulate.a = 0.0
	sub_lbl.modulate.a = 0.0


func popup(text: String, color: Color = Color(1, 0.9, 0.45)) -> void:
	popup_lbl.text = text
	popup_lbl.add_theme_color_override("font_color", color)
	if _popup_tween:
		_popup_tween.kill()
	popup_lbl.modulate.a = 1.0
	popup_lbl.position.y = popup_lbl.position.y
	_popup_tween = create_tween()
	_popup_tween.tween_interval(1.3)
	_popup_tween.tween_property(popup_lbl, "modulate:a", 0.0, 0.4)


func add_feed(text: String, color: Color = Color.WHITE) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.05, 0.1, 0.7), 10))
	var l := UiTheme.label(text, 20, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if not Loc.is_rtl() else HORIZONTAL_ALIGNMENT_LEFT
	p.add_child(l)
	feed.add_child(p)
	if feed.get_child_count() > 4:
		feed.get_child(0).queue_free()
	var tw := p.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func set_replay(on: bool) -> void:
	replay_banner.visible = on


func _process(_delta: float) -> void:
	if Settings.get_value("show_fps", false):
		fps_lbl.text = "%d FPS" % Engine.get_frames_per_second()
	else:
		fps_lbl.text = ""
	queue_redraw()


func _draw() -> void:
	if not show_ball_indicator or camera == null or not is_visible_in_tree():
		return
	var vp := get_viewport_rect().size
	var behind := camera.is_position_behind(ball_pos)
	var sp := camera.unproject_position(ball_pos)
	var margin := 48.0
	var on_screen := not behind and sp.x > margin and sp.x < vp.x - margin and sp.y > margin and sp.y < vp.y - margin
	if on_screen:
		return
	var center := vp * 0.5
	var dir := sp - center
	if behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var half := vp * 0.5 - Vector2(margin, margin)
	var t := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var p := center + dir * t
	var col := Color(1, 1, 1, 0.85)
	draw_circle(p, 20, Color(0.05, 0.08, 0.14, 0.75))
	draw_arc(p, 20, 0, TAU, 32, col, 2.5, true)
	draw_circle(p, 9, col)
	var tip := p + dir * 34
	var side := Vector2(-dir.y, dir.x) * 10
	draw_colored_polygon(PackedVector2Array([tip, p + dir * 22 + side, p + dir * 22 - side]), col)
