class_name HUD
extends CanvasLayer
## Race HUD (built in code). Compact, outlined, kept to the screen edges so the
## road stays visible on phones.

var race: RaceManager
var player: Kart
var items: ItemSystem
var tb: TrackBuilder

var _root: Control
var _pos: Label
var _pos_suffix: Label
var _lap: Label
var _time: Label
var _lap_time: Label
var _best: Label
var _msg: Label
var _count: Label
var _fps: Label
var _gauge: HudGauge
var _map: HudMinimap
var _item: HudItem
var _msg_t := 0.0


func setup(r: RaceManager, k: Kart, it: ItemSystem, builder: TrackBuilder) -> void:
	race = r
	player = k
	items = it
	tb = builder
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UIKit.safe_margins(_root)
	# top-left: position + lap
	_pos = UIKit.label("1", 92, UIKit.CREAM, 14)
	_pos.position = Vector2(18, 0)
	_root.add_child(_pos)
	_pos_suffix = UIKit.label("st", 40, UIKit.CREAM, 10)
	_pos_suffix.position = Vector2(82, 14)
	_root.add_child(_pos_suffix)
	_lap = UIKit.label("LAP 1/3", 34, UIKit.CREAM, 8)
	_lap.position = Vector2(22, 108)
	_root.add_child(_lap)
	# top-right: times
	var tv := VBoxContainer.new()
	tv.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tv.position = Vector2(-330, 8)
	tv.custom_minimum_size = Vector2(310, 0)
	tv.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(tv)
	_time = UIKit.label("0:00.000", 36, UIKit.CREAM, 8)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tv.add_child(_time)
	_lap_time = UIKit.label("LAP 0:00.000", 24, Color(0.85, 0.9, 1.0), 6)
	_lap_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tv.add_child(_lap_time)
	_best = UIKit.label("BEST --:--.---", 22, Color(1.0, 0.85, 0.4), 6)
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tv.add_child(_best)
	# minimap under the times
	_map = HudMinimap.new()
	_map.setup(tb, race, player)
	_map.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_map.position = Vector2(-250, 120)
	_map.custom_minimum_size = Vector2(230, 230)
	_map.size = Vector2(230, 230)
	_root.add_child(_map)
	# item slot top-centre-left
	_item = HudItem.new()
	_item.setup(items, player)
	_item.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_item.position = Vector2(-260, 8)
	_item.size = Vector2(120, 120)
	_root.add_child(_item)
	# speed / reserve / drift gauge bottom-centre
	_gauge = HudGauge.new()
	_gauge.kart = player
	_gauge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge.position = Vector2(-190, -190)
	_gauge.size = Vector2(380, 180)
	_root.add_child(_gauge)
	# centre messages
	_msg = UIKit.label("", 54, UIKit.CREAM, 12)
	_msg.set_anchors_preset(Control.PRESET_CENTER)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.position = Vector2(-400, -170)
	_msg.size = Vector2(800, 80)
	_root.add_child(_msg)
	_count = UIKit.label("", 180, UIKit.ORANGE, 22)
	_count.set_anchors_preset(Control.PRESET_CENTER)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.position = Vector2(-300, -160)
	_count.size = Vector2(600, 220)
	_root.add_child(_count)
	_fps = UIKit.label("", 20, Color(0.7, 1, 0.7), 4)
	_fps.position = Vector2(22, 156)
	_root.add_child(_fps)
	race.countdown_tick.connect(_on_count)
	race.notify.connect(_on_notify)
	player.spark.connect(func(stage: int, _q: float, perfect: bool, hooked: bool) -> void:
		if hooked:
			flash("HOOK BOOST!", Color(0.75, 0.5, 1.0))
		elif perfect:
			flash("PERFECT x%d" % (stage + 1), Color(1.0, 0.4, 0.45))
		else:
			flash("BOOST x%d" % (stage + 1), UIKit.ORANGE, 0.5))
	player.fizzle.connect(func(reason: StringName) -> void:
		flash("TOO LATE" if reason == &"late" else "TOO EARLY", Color(0.7, 0.7, 0.75), 0.6))
	player.boost_gained.connect(func(amount: float, source: StringName) -> void:
		if source == &"air":
			flash("AIR BOOST +%.1f" % amount, UIKit.TEAL, 0.8))
	player.tier_changed.connect(func(t: int) -> void:
		if t == 2:
			flash("OVERDRIVE!", UIKit.TEAL))


func flash(text: String, color := UIKit.CREAM, dur := 1.0) -> void:
	_msg.text = text
	_msg.label_settings.font_color = color
	_msg_t = dur
	_msg.scale = Vector2(1.25, 1.25)
	_msg.pivot_offset = _msg.size * 0.5
	create_tween().tween_property(_msg, "scale", Vector2.ONE, 0.18)


func _on_count(n: int) -> void:
	_count.text = "GO!" if n == 0 else str(n)
	_count.label_settings.font_color = Color(0.3, 1.0, 0.4) if n == 0 else UIKit.ORANGE
	_count.pivot_offset = _count.size * 0.5
	_count.scale = Vector2(1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(_count, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	if n == 0:
		tw.tween_interval(0.6)
		tw.tween_callback(func() -> void: _count.text = "")
	Sfx.play("beep_high" if n == 0 else "beep_low")


func _on_notify(k: Kart, text: String, color: Color) -> void:
	if k != player or text == "":
		return
	flash(text, color, 1.4)
	if text.begins_with("LAP"):
		Sfx.play("lap")
	elif text == "FINAL LAP":
		Sfx.play("final_lap")


func _process(dt: float) -> void:
	if race == null:
		return
	var pos := race.position_of(player)
	_pos.text = str(pos)
	_pos_suffix.text = ["th", "st", "nd", "rd"][pos] if pos <= 3 else "th"
	_pos_suffix.position.x = 18 + _pos.get_minimum_size().x - 4
	var pr := race.progress_of(player)
	_lap.text = "LAP %d/%d" % [race.lap_of(player), race.laps]
	_time.text = Game.format_time(race.race_time)
	var lt := race.race_time - float(pr.lap_start) if int(pr.lap) >= 1 else 0.0
	_lap_time.text = "LAP " + Game.format_time(lt)
	_best.text = "BEST " + Game.format_time(float(pr.best))
	if _msg_t > 0.0:
		_msg_t -= dt
		if _msg_t <= 0.0:
			_msg.text = ""
	if Game.settings["show_fps"]:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
	else:
		_fps.text = ""
	_gauge.queue_redraw()
	_map.queue_redraw()
	_item.queue_redraw()
