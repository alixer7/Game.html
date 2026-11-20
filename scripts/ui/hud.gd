class_name HUD
extends CanvasLayer
## In-game HUD: speedometer, minimap, race info, messages, pursuit meters,
## checkpoint arrow, event prompt and challenge panel.

signal start_event_pressed(event: Dictionary)

var root: Control
var speedo: Speedo
var minimap: Minimap
var race_box: VBoxContainer
var pos_label: Label
var lap_label: Label
var time_label: Label
var msg_big: Label
var msg_small: Label
var _big_t := 0.0
var _small_t := 0.0
var heat_box: Control
var heat_label: Label
var bust_bar: ProgressBar
var prompt_btn: Button
var prompt_event: Dictionary = {}
var region_label: Label
var _region_t := 0.0
var _last_region := ""
var arrow: Arrow
var challenge_label: Label
var fps_label: Label
var wrong_label: Label


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	add_child(root)
	speedo = Speedo.new()
	root.add_child(speedo)
	minimap = Minimap.new()
	root.add_child(minimap)
	# race info (top centre)
	race_box = VBoxContainer.new()
	race_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	race_box.position = Vector2(-160, 8)
	race_box.custom_minimum_size = Vector2(320, 0)
	race_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	race_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(race_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	race_box.add_child(row)
	pos_label = UITheme.label("", 44, 800)
	lap_label = UITheme.label("", 24, 700, UITheme.DIM)
	time_label = UITheme.label("", 26, 700)
	row.add_child(pos_label)
	var col := VBoxContainer.new()
	col.add_child(time_label)
	col.add_child(lap_label)
	row.add_child(col)
	arrow = Arrow.new()
	arrow.custom_minimum_size = Vector2(320, 44)
	race_box.add_child(arrow)
	# messages
	msg_big = UITheme.label("", 72, 800)
	msg_big.set_anchors_preset(Control.PRESET_CENTER)
	msg_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_big.position = Vector2(-500, -150)
	msg_big.size = Vector2(1000, 100)
	root.add_child(msg_big)
	msg_small = UITheme.label("", 26, 700)
	msg_small.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_small.position = Vector2(-380, 150)
	msg_small.size = Vector2(760, 80)
	root.add_child(msg_small)
	wrong_label = UITheme.label(Game.t("wrong_way"), 40, 800, Color(1, 0.3, 0.25))
	wrong_label.set_anchors_preset(Control.PRESET_CENTER)
	wrong_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrong_label.position = Vector2(-300, -60)
	wrong_label.size = Vector2(600, 60)
	wrong_label.visible = false
	root.add_child(wrong_label)
	# pursuit
	heat_box = VBoxContainer.new()
	heat_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	heat_box.position = Vector2(-250, 110)
	heat_box.custom_minimum_size = Vector2(220, 0)
	heat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(heat_box)
	heat_label = UITheme.label("", 22, 700, Color(1, 0.45, 0.45))
	heat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heat_box.add_child(heat_label)
	bust_bar = ProgressBar.new()
	bust_bar.custom_minimum_size = Vector2(220, 14)
	bust_bar.show_percentage = false
	bust_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0.2, 0.2)
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(6)
	bust_bar.add_theme_stylebox_override("fill", fill)
	bust_bar.add_theme_stylebox_override("background", bg)
	heat_box.add_child(bust_bar)
	heat_box.visible = false
	# event prompt
	prompt_btn = UITheme.button("", 26, 420)
	prompt_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_btn.position = Vector2(-210, -250)
	prompt_btn.visible = false
	prompt_btn.pressed.connect(func(): start_event_pressed.emit(prompt_event))
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.9)
	ps.set_corner_radius_all(16)
	prompt_btn.add_theme_stylebox_override("normal", ps)
	root.add_child(prompt_btn)
	region_label = UITheme.label("", 30, 700)
	region_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_label.position = Vector2(-300, 96)
	region_label.size = Vector2(600, 40)
	root.add_child(region_label)
	challenge_label = UITheme.label("", 30, 800, Color(0.85, 0.65, 1.0))
	challenge_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	challenge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_label.position = Vector2(-300, 20)
	challenge_label.size = Vector2(600, 90)
	root.add_child(challenge_label)
	fps_label = UITheme.label("", 16, 600, UITheme.DIM)
	fps_label.position = Vector2(10, 4)
	fps_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fps_label.position = Vector2(8, -26)
	root.add_child(fps_label)


func show_message(text: String, color: Color, big: bool) -> void:
	if big:
		msg_big.text = text
		msg_big.add_theme_color_override("font_color", color)
		msg_big.scale = Vector2.ONE * 1.25
		msg_big.pivot_offset = msg_big.size * 0.5
		_big_t = 1.6
	else:
		msg_small.text = text
		msg_small.add_theme_color_override("font_color", color)
		_small_t = 3.2


func _layout() -> void:
	var vp := root.get_viewport_rect().size
	root.position = Vector2.ZERO
	root.size = vp
	speedo.position = Vector2(vp.x * 0.5 - speedo.size.x * 0.5, vp.y - speedo.size.y - 6.0)
	minimap.position = Vector2(14, 84)
	race_box.position = Vector2(vp.x * 0.5 - race_box.size.x * 0.5, 8)
	msg_big.position = Vector2(vp.x * 0.5 - msg_big.size.x * 0.5, vp.y * 0.28)
	msg_small.position = Vector2(vp.x * 0.5 - msg_small.size.x * 0.5, vp.y * 0.2)
	wrong_label.position = Vector2(vp.x * 0.5 - wrong_label.size.x * 0.5, vp.y * 0.4)
	heat_box.position = Vector2(vp.x - heat_box.size.x - 24.0, 110)
	prompt_btn.position = Vector2(vp.x * 0.5 - prompt_btn.size.x * 0.5, vp.y - 250.0)
	region_label.position = Vector2(vp.x * 0.5 - region_label.size.x * 0.5, 96)
	challenge_label.position = Vector2(vp.x * 0.5 - challenge_label.size.x * 0.5, 20)
	fps_label.position = Vector2(8, vp.y - 26)


func _process(delta: float) -> void:
	_layout()
	var real := delta / maxf(Engine.time_scale, 0.05)
	_big_t -= real
	_small_t -= real
	msg_big.modulate.a = clampf(_big_t * 2.0, 0.0, 1.0)
	msg_big.scale = msg_big.scale.lerp(Vector2.ONE, clampf(real * 8.0, 0, 1))
	msg_small.modulate.a = clampf(_small_t * 2.0, 0.0, 1.0)
	var car: Car = Game.player
	if car == null:
		return
	speedo.car = car
	speedo.queue_redraw()
	minimap.queue_redraw()
	minimap.update_view(car)
	fps_label.visible = Game.settings.show_fps
	if fps_label.visible:
		fps_label.text = "%d %s" % [Engine.get_frames_per_second(), Game.t("fps")]
	var race: RaceManager = Game.race
	var racing := race != null and race.state != RaceManager.IDLE and not race.player_entry.is_empty()
	race_box.visible = racing
	if racing:
		var pe: Dictionary = race.player_entry
		pos_label.text = "%d/%d" % [pe.get("pos", 0), race.racers.size()]
		time_label.text = Game.format_time(race.time)
		var cps_total := race.cps.size()
		if race.laps > 1:
			lap_label.text = "%s %d/%d   •   %s %d/%d" % [Game.t("lap"), mini(pe.lap + 1, race.laps), race.laps, Game.t("checkpoint"), pe.cp, cps_total]
		else:
			lap_label.text = "%s %d/%d" % [Game.t("checkpoint"), pe.cp, cps_total]
		var tgt := race.next_checkpoint_pos()
		arrow.visible = tgt != Vector3.INF
		if arrow.visible:
			var loc := car.to_local(tgt)
			arrow.angle = atan2(loc.x, -loc.z)
			arrow.dist = Vector2(loc.x, loc.z).length()
			arrow.alert = race.missed
			arrow.queue_redraw()
		wrong_label.visible = race.is_wrong_way()
	else:
		wrong_label.visible = false
	# pursuit
	var pur: Pursuit = race.pursuit if race else null
	heat_box.visible = pur != null and pur.active and pur.units.size() > 0
	if heat_box.visible:
		heat_label.text = "%s  %s" % [Game.t("heat"), "★".repeat(pur.heat) + "☆".repeat(3 - pur.heat)]
		bust_bar.value = pur.bust_meter
	# challenge
	if race and race.challenge != "":
		var txt := ""
		if race.challenge == "drift":
			txt = "%s  %d   x%.1f\n%d s" % [Game.t("score"), int(race.ch_score), race.ch_combo, int(race.ch_time)]
		else:
			txt = "%s  %.1f m\n%d s" % [Game.t("jump_dist"), race.ch_best_jump, int(race.ch_time)]
		challenge_label.text = txt
		challenge_label.visible = true
	else:
		challenge_label.visible = false
	# event prompt in free roam
	prompt_btn.visible = false
	if race and race.state == RaceManager.IDLE and race.challenge == "" and car.speed_abs < 14.0:
		var mk := race.marker_near(car.global_position, 11.0)
		if not mk.is_empty():
			prompt_event = mk.event
			var nm: String = mk.event.name_ar if Game.settings.lang == "ar" else mk.event.name_en
			prompt_btn.text = "▶  %s  —  %s" % [nm, Game.t("race_here")]
			prompt_btn.visible = true
	# region name banner
	_region_t -= real
	if Engine.get_process_frames() % 30 == 0 and Game.world:
		var reg: String = Game.world.data.region_name(car.global_position)
		if reg != _last_region:
			_last_region = reg
			region_label.text = Game.t(reg)
			_region_t = 3.0
	region_label.modulate.a = clampf(_region_t, 0.0, 1.0)
	region_label.visible = not racing


# --------------------------------------------------------------------------- widgets
class Speedo extends Control:
	var car: Car

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		custom_minimum_size = Vector2(240, 160)
		size = Vector2(240, 160)
		position = Vector2(-120, -170)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if car == null:
			return
		var c := Vector2(size.x * 0.5, size.y * 0.62)
		var r := 92.0
		var a0 := PI * 0.8
		var a1 := PI * 2.2
		draw_arc(c, r, a0, a1, 64, Color(0, 0, 0, 0.45), 16, true)
		var red: float = car.spec.redline
		var t := clampf(car.rpm / red, 0.0, 1.0)
		var col := UITheme.ACCENT2.lerp(Color(1, 0.25, 0.2), smoothstep(0.75, 0.95, t))
		draw_arc(c, r, a0, lerpf(a0, a1, t), 64, col, 10, true)
		for k in 9:
			var a := lerpf(a0, a1, k / 8.0)
			draw_line(c + Vector2(cos(a), sin(a)) * (r - 14), c + Vector2(cos(a), sin(a)) * (r - 4), Color(1, 1, 1, 0.5), 2)
		var f := UITheme.font(800)
		var sp := Game.speed_text(car.speed_abs)
		draw_string(f, c + Vector2(-90, 12), sp, HORIZONTAL_ALIGNMENT_CENTER, 180, 56, Color.WHITE)
		draw_string(UITheme.font(600), c + Vector2(-90, 38), Game.speed_unit(), HORIZONTAL_ALIGNMENT_CENTER, 180, 16, UITheme.DIM)
		var g := "R" if car.gear < 0 else ("N" if car.gear == 0 else str(car.gear))
		draw_string(f, c + Vector2(-20, -40), g, HORIZONTAL_ALIGNMENT_CENTER, 40, 28, UITheme.ACCENT)
		# nitro bar
		var bw := 150.0
		var bp := c + Vector2(-bw * 0.5, 54)
		draw_rect(Rect2(bp, Vector2(bw, 9)), Color(0, 0, 0, 0.5))
		var ncol := Color(0.3, 0.6, 1.0) if not car.nitro_active else Color(0.6, 0.85, 1.0)
		draw_rect(Rect2(bp, Vector2(bw * car.nitro, 9)), ncol)
		draw_string(UITheme.font(700), bp + Vector2(bw + 6, 10), "N₂O", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ncol)
		# damage indicator
		if car.damage > 0.05:
			draw_rect(Rect2(bp + Vector2(0, 14), Vector2(bw * car.damage, 4)), Color(1, 0.4, 0.2, 0.8))


class Minimap extends Control:
	var mat: ShaderMaterial
	var rect: ColorRect
	var overlay: Control
	var zoom := 0.1
	var car: Car

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		position = Vector2(14, 84)
		size = Vector2(190, 190)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect = ColorRect.new()
		rect.size = size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mat = ShaderMaterial.new()
		mat.shader = load("res://shaders/minimap.gdshader")
		mat.set_shader_parameter("map_tex", load("res://assets/world/map.png"))
		rect.material = mat
		add_child(rect)
		overlay = Control.new()
		overlay.size = size
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.draw.connect(_draw_overlay)
		add_child(overlay)

	func update_view(c: Car) -> void:
		car = c
		var p := c.get_global_transform_interpolated().origin
		var fwd := -c.get_global_transform_interpolated().basis.z
		var th := atan2(fwd.x, -fwd.z)
		zoom = lerpf(zoom, clampf(0.07 + c.speed_abs / 900.0, 0.07, 0.16), 0.05)
		mat.set_shader_parameter("center_uv", Vector2((p.x + 2048.0) / 4096.0, (p.z + 2048.0) / 4096.0))
		mat.set_shader_parameter("rot", th)
		mat.set_shader_parameter("zoom", zoom)
		overlay.queue_redraw()

	func to_screen(w: Vector3) -> Vector2:
		var p := car.global_position
		var fwd := -car.global_transform.basis.z
		var th := atan2(fwd.x, -fwd.z)
		var rel := Vector2(w.x - p.x, w.z - p.z) / (4096.0 * zoom)
		var q := rel.rotated(-th)
		return size * 0.5 + q * size.x

	func _draw_overlay() -> void:
		if car == null:
			return
		var rad := size.x * 0.47
		var center := size * 0.5
		var race: RaceManager = Game.race
		if race:
			# race route
			if race.route and race.state != RaceManager.IDLE:
				var prev := Vector2.INF
				var step := 3
				for i in range(0, race.route.pts.size(), step):
					var s := to_screen(race.route.pts[i])
					if s.distance_to(center) < rad and prev != Vector2.INF and prev.distance_to(center) < rad:
						overlay.draw_line(prev, s, Color(1.0, 0.55, 0.15, 0.85), 3.0, true)
					prev = s
				var cp := race.next_checkpoint_pos()
				if cp != Vector3.INF:
					var s := to_screen(cp)
					if s.distance_to(center) > rad - 8:
						s = center + (s - center).normalized() * (rad - 8)
					overlay.draw_circle(s, 7, Color(1, 0.85, 0.2))
				for r in race.racers:
					if r.is_player or not is_instance_valid(r.car):
						continue
					var s := to_screen(r.car.global_position)
					if s.distance_to(center) < rad:
						overlay.draw_circle(s, 4.5, Color(0.95, 0.95, 0.95))
				var t := Time.get_ticks_msec() * 0.001
				for u in race.pursuit.units:
					if is_instance_valid(u):
						var s := to_screen(u.global_position)
						if s.distance_to(center) < rad:
							overlay.draw_circle(s, 5.0, Color(1, 0.15, 0.15) if fmod(t * 4.0, 1.0) < 0.5 else Color(0.2, 0.4, 1.0))
			else:
				for mk in race.markers:
					var s := to_screen(mk.pos)
					if s.distance_to(center) > rad - 8:
						s = center + (s - center).normalized() * (rad - 8)
					overlay.draw_circle(s, 6, mk.color)
		# player arrow
		var a := PackedVector2Array([center + Vector2(0, -10), center + Vector2(7, 8), center + Vector2(0, 4), center + Vector2(-7, 8)])
		overlay.draw_colored_polygon(a, Color(1, 1, 1))


class Arrow extends Control:
	var angle := 0.0
	var dist := 0.0
	var alert := false

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 22)
		var col := Color(1, 0.35, 0.3) if alert else Color(1, 0.85, 0.25)
		var pts := PackedVector2Array([Vector2(0, -16), Vector2(12, 10), Vector2(0, 4), Vector2(-12, 10)])
		for i in pts.size():
			pts[i] = c + Vector2(-60, 0) + pts[i].rotated(angle)
		draw_colored_polygon(pts, col)
		draw_string(UITheme.font(700), c + Vector2(-35, 9), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
