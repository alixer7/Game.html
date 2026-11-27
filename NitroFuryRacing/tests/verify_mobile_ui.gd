extends Node

## Exhaustive Mobile UI, Arabic RTL Safety, Touch-Button Zero-Overlap & Visual Capture Verifier!
## Simulates a real 20:9 Arabic Android smartphone (1600x720) with OS RTL locale active!

const OUT_DIR := "C:/Users/ali77/.gemini/antigravity/brain/f77adea1-50f1-415f-8265-46a6675cf481"
var failures: Array[String] = []

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] ", msg)
	else:
		print("  [FAIL] ", msg)
		failures.append(msg)

func _ready() -> void:
	print("\n============================================================")
	print("  MOBILE 20:9 ARABIC-PHONE UI & TOUCH OVERLAP VERIFICATION")
	print("============================================================\n")

	# Simulate 20:9 Android phone (Samsung Galaxy / Pixel landscape)
	get_window().size = Vector2i(1600, 720)
	TranslationServer.set_locale("ar")
	GameState.language = "ar"
	await _wait(6)

	var vp := get_viewport().get_visible_rect().size
	print("  Simulated Phone Viewport: ", vp)

	# --- 1. VERIFY ALL MAIN MENU SCREENS ---
	var menu := MainMenu.new()
	add_child(menu)
	await _wait(12)
	_assert(not menu._ui_root.is_layout_rtl(), "MainMenu _ui_root locked to LTR coordinate space (Arabic text still RTL!)")
	_verify_all_buttons_onscreen(menu._ui_root, vp, "HOME")
	await _snap("phone_01_home.png")

	menu._current_screen = MainMenu.Screen.RACER_SELECT
	menu._render_screen()
	await _wait(8)
	_verify_all_buttons_onscreen(menu._ui_root, vp, "RACER_SELECT")
	await _snap("phone_02_racer.png")

	menu._current_screen = MainMenu.Screen.TRACK_SELECT
	menu._render_screen()
	await _wait(8)
	_verify_all_buttons_onscreen(menu._ui_root, vp, "TRACK_SELECT")
	await _snap("phone_03_track.png")

	menu._current_screen = MainMenu.Screen.SETTINGS
	menu._render_screen()
	await _wait(8)
	_verify_all_buttons_onscreen(menu._ui_root, vp, "SETTINGS")
	await _snap("phone_04_settings.png")

	menu._current_screen = MainMenu.Screen.GUIDE
	menu._render_screen()
	await _wait(8)
	_verify_all_buttons_onscreen(menu._ui_root, vp, "GUIDE")

	menu.queue_free()
	await _wait(4)

	# --- 2. VERIFY GAMEPLAY HUD + TOUCH CONTROLS (ZERO OVERLAP!) ---
	GameState.selected_mode = GameState.GameMode.ARCADE_RACE
	GameState.selected_track_index = 0
	GameState.auto_accelerate = false # Test with ALL touch buttons visible including GAS!
	var race := RaceManager.new()
	add_child(race)
	await _wait(8)

	race.countdown_timer = 0.0
	race.race_active = true
	if race.hud: race.hud.set_countdown(0)
	for k in race.all_karts:
		k.race_started = true

	var sp: TrackSpline = race.built_data["spline"]
	var s := sp.sample_at_t(0.215)
	race.player_kart.global_position = s["pos"] + Vector3(0.0, 0.5, 0.0)
	race.player_kart.heading_yaw = atan2(-s["forward"].x, -s["forward"].z)
	race.player_kart.spline_t = 0.215
	race.player_kart.add_fruit(10)
	race.player_kart.held_item = "missile"
	race.player_kart.item_roulette_timer = 0.0
	race.player_kart.trigger_turbo_pad(false)
	race.race_camera.attach_to(race.player_kart)
	await _wait(16)

	_assert(not race.hud.is_layout_rtl(), "RaceHUD locked to LTR coordinate space")
	_verify_all_buttons_onscreen(race.hud, vp, "RACE_HUD")
	_verify_touch_controls(race.touch_controls, race.hud, vp)
	await _snap("phone_05_gameplay_hud.png")

	# Verify Pause Modal buttons
	race._toggle_pause()
	await _wait(6)
	_verify_all_buttons_onscreen(race.hud._pause_overlay, vp, "PAUSE_MODAL")
	await _snap("phone_06_pause.png")
	race._toggle_pause()

	# Restore default auto-accelerate ON
	GameState.auto_accelerate = true
	GameState.save_data()
	race.queue_free()
	await _wait(4)

	print("\n============================================================")
	if failures.is_empty():
		print("  ALL MOBILE UI & TOUCH OVERLAP CHECKS PASSED! (0 failures)")
		print("============================================================\n")
		get_tree().quit(0)
	else:
		print("  FAILED: ", failures.size(), " UI issue(s):")
		for f in failures:
			print("    - ", f)
		print("============================================================\n")
		get_tree().quit(1)

func _verify_all_buttons_onscreen(root_ctl: Control, vp: Vector2, screen_name: String) -> void:
	var btns: Array[Button] = []
	_collect_buttons(root_ctl, btns)
	_assert(btns.size() > 0, "%s has %d visible clickable button(s)" % [screen_name, btns.size()])
	for b in btns:
		var r := b.get_global_rect()
		var inside := r.position.x >= -1.0 and r.position.y >= -1.0 and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0 and r.size.x >= 40.0 and r.size.y >= 36.0
		_assert(inside, "%s button '%s' cleanly on-screen: %s" % [screen_name, b.text.replace("\n", " "), str(r)])

func _collect_buttons(node: Node, out: Array[Button]) -> void:
	if node is Control and not node.visible:
		return
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_collect_buttons(c, out)

func _verify_touch_controls(tc, hud, vp: Vector2) -> void:
	var btns: Array = tc.get_debug_buttons()
	_assert(btns.size() >= 8, "All 8 mobile touch buttons present (incl. Rear-View & Gas): %d" % btns.size())
	# 1. Every touch button completely inside viewport!
	for b in btns:
		var r: Rect2 = b["rect"]
		var inside := r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= vp.x and r.end.y <= vp.y
		_assert(inside, "Touch button '%s' inside phone screen: %s" % [b["name"], str(r)])
	# 2. ZERO pairwise overlap among touch buttons!
	for i in range(btns.size()):
		for j in range(i + 1, btns.size()):
			var ri: Rect2 = btns[i]["rect"]
			var rj: Rect2 = btns[j]["rect"]
			_assert(not ri.intersects(rj), "Zero overlap between touch '%s' and '%s'" % [btns[i]["name"], btns[j]["name"]])
	# 3. ZERO overlap between Touch Controls and Minimap / Boost Gauge!
	var mm_rect: Rect2 = hud._minimap.get_global_rect()
	var bg_rect: Rect2 = hud._boost_gauge.get_global_rect()
	for b in btns:
		var r: Rect2 = b["rect"]
		_assert(not r.intersects(mm_rect), "Touch '%s' does not overlap Minimap" % b["name"])
		_assert(not r.intersects(bg_rect), "Touch '%s' does not overlap Boost/Speedometer Gauge" % b["name"])

func _wait(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame

func _snap(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(OUT_DIR + "/" + filename)
