class_name SettingsPanel
extends Control
## Settings: graphics / audio / controls (incl. touch layout editor) / gameplay.

signal closed()

var _tabs: TabContainer
var _editor: TouchControls


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	add_child(panel)
	UIKit.safe_margins(panel)   # full screen minus notches/rounded corners
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UIKit.label("SETTINGS", 46, UIKit.ORANGE, 10)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.button("Done", _close, 200))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_tabs.add_child(_graphics())
	_tabs.add_child(_audio())
	_tabs.add_child(_controls())
	_tabs.add_child(_gameplay())


func _page(name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 28   # a tap with a little finger movement is still a tap
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _graphics() -> Control:
	var v := _page("Graphics")
	var s := Game.settings
	v.add_child(UIKit.row("Quality preset", UIKit.options(["Low", "Medium", "High"], int(s.quality), func(i: int) -> void: s.quality = i)))
	v.add_child(UIKit.label("(Quality changes vegetation density, view distance and shadows; applied on the next race.)", 20, Color(0.8, 0.85, 0.9), 4))
	v.add_child(UIKit.row("Render scale", UIKit.slider(0.5, 1.0, 0.05, float(s.render_scale), func(x: float) -> void:
		s.render_scale = x
		Game.apply_settings())))
	v.add_child(UIKit.row("FPS cap", UIKit.options(["30", "60", "120"], [30, 60, 120].find(int(s.fps_cap)), func(i: int) -> void:
		s.fps_cap = [30, 60, 120][i]
		Game.apply_settings())))
	v.add_child(UIKit.row("Shadows", UIKit.toggle(bool(s.shadows), func(b: bool) -> void: s.shadows = b)))
	v.add_child(UIKit.row("Screen edge margin", UIKit.slider(0.0, 0.06, 0.005, float(s.get("screen_margin", 0.02)), func(x: float) -> void:
		s.screen_margin = x
		get_viewport().size_changed.emit())))   # every safe-area layout re-applies
	v.add_child(UIKit.row("Show FPS", UIKit.toggle(bool(s.show_fps), func(b: bool) -> void: s.show_fps = b)))
	return v.get_parent()


func _audio() -> Control:
	var v := _page("Audio")
	var s := Game.settings
	for pair in [["Master", "vol_master"], ["Music", "vol_music"], ["Effects", "vol_sfx"]]:
		var key: String = pair[1]
		v.add_child(UIKit.row(pair[0], UIKit.slider(0.0, 1.0, 0.05, float(s[key]), func(x: float) -> void:
			s[key] = x
			Game.apply_settings())))
	return v.get_parent()


func _controls() -> Control:
	var v := _page("Controls")
	var s := Game.settings
	v.add_child(UIKit.row("Auto-accelerate", UIKit.toggle(bool(s.auto_accel), func(b: bool) -> void: s.auto_accel = b)))
	v.add_child(UIKit.row("Steering sensitivity", UIKit.slider(0.5, 1.5, 0.05, float(s.steer_sensitivity), func(x: float) -> void: s.steer_sensitivity = x)))
	v.add_child(UIKit.row("Button size", UIKit.slider(0.7, 1.5, 0.05, float(s.touch_scale), func(x: float) -> void:
		s.touch_scale = x
		if _editor: _editor.queue_redraw())))
	v.add_child(UIKit.row("Button opacity", UIKit.slider(0.2, 1.0, 0.05, float(s.touch_opacity), func(x: float) -> void:
		s.touch_opacity = x
		if _editor: _editor.queue_redraw())))
	v.add_child(UIKit.row("Vibration", UIKit.toggle(bool(s.haptics), func(b: bool) -> void: s.haptics = b)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	hb.add_child(UIKit.button("Edit touch layout", _edit_layout, 360))
	hb.add_child(UIKit.button("Reset layout", func() -> void:
		s.touch_layout = {}
		Game.save_settings(), 300))
	v.add_child(hb)
	v.add_child(UIKit.label("Touch: steer with the left thumb. Hold DRIFT to power-slide; tap DRIFT again (or BOOST)\nwhen the meter glows to spark-boost. Pull the stick back while sliding to hook-turn.", 20, Color(0.85, 0.9, 1.0), 4))
	v.add_child(UIKit.label("Keyboard: W/S or arrows, A/D steer, SPACE drift, SHIFT boost, F item, C look back, ESC pause.\nGamepad: A/RT accelerate, B/LT brake, RB drift, LB boost, X item, Y look back.", 20, Color(0.85, 0.9, 1.0), 4))
	return v.get_parent()


func _gameplay() -> Control:
	var v := _page("Gameplay")
	var s := Game.settings
	v.add_child(UIKit.row("Opponent catch-up", UIKit.options(["Off", "Light (default)", "Classic"], int(s.rubber_band), func(i: int) -> void: s.rubber_band = i)))
	v.add_child(UIKit.label("Catch-up never exceeds +3% top speed and only helps AI far behind you.", 20, Color(0.8, 0.85, 0.9), 4))
	return v.get_parent()


func _edit_layout() -> void:
	if _editor:
		_editor.queue_free()
		_editor = null
		Game.save_settings()
		return
	_editor = TouchControls.new()
	_editor.edit_mode = true
	add_child(_editor)
	_editor.visible = true
	_editor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tabs.visible = false
	var done := UIKit.button("Finish editing", func() -> void:
		_editor.queue_free()
		_editor = null
		_tabs.visible = true
		Game.save_settings(), 360)
	done.name = "FinishEdit"
	done.set_anchors_preset(Control.PRESET_CENTER_TOP)
	done.position = Vector2(-180, 120)
	add_child(done)
	done.pressed.connect(done.queue_free)


func _close() -> void:
	Game.save_settings()
	Game.apply_settings()
	closed.emit()
	queue_free()
