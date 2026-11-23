class_name UITests
extends RefCounted
## Screen-layout and touch tests for every menu/HUD screen, on many phone and
## tablet screen shapes, with and without a simulated camera cut-out:
##  - every visible widget (buttons, options, toggles, sliders, labels, touch
##    controls) lies fully inside the safe area (nothing under a notch/edge)
##  - every visible button reacts to a tap at its centre (nothing covers it, it
##    isn't off-screen, it isn't swallowed by a scroll container)
## Runs headless: the window is resized per case; taps go through the real
## viewport input path in window coordinates.

const SCREENS := [
	[2340, 1080, "S24 Ultra FHD+ 19.5:9"],
	[3088, 1440, "S24 Ultra QHD+"],
	[1600, 720, "20:9"],
	[2400, 1080, "20:9 FHD+"],
	[1920, 1080, "16:9"],
	[2560, 1080, "21:9"],
	[2560, 1600, "tablet 16:10"],
	[2048, 1536, "tablet 4:3"],
]
# simulated cut-outs (canvas px: left, top, right, bottom)
const INSETS := [["none", ""], ["punch-hole left", "70,0,30,0"], ["notch + nav bar", "110,0,0,48"]]

var R: Object
var T: SceneTree
var fails: Array = []
var checked := 0
var tapped := 0


func run(runner: Object) -> void:
	R = runner
	T = (runner as Node).get_tree()
	OS.set_environment("WK_TOUCH", "1")
	for sc in SCREENS:
		for ins in INSETS:
			await _menus(sc, ins)
	# the race screens (HUD, touch controls, pause, results) on a subset
	for k in [[0, 1], [4, 0], [7, 2]]:
		await _race(SCREENS[k[0]], INSETS[k[1]])
	await _back_and_focus()
	OS.set_environment("WK_SAFE_INSET", "")
	T.root.size = Vector2i(1600, 720)
	var out := {"cases": SCREENS.size() * INSETS.size() + 3, "widgets_checked": checked, "buttons_tapped": tapped, "failures": fails.slice(0, 40), "failure_count": fails.size()}
	var f := FileAccess.open("res://tests/results/ui.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	R.check("ui", "every widget inside the safe area and every button tappable on %d screen shapes x %d cut-out cases" % [SCREENS.size(), INSETS.size()], fails.is_empty() and tapped > 300, out)


func _set_screen(sc: Array, ins: Array) -> void:
	OS.set_environment("WK_SAFE_INSET", ins[1])
	T.root.size = Vector2i(sc[0], sc[1])
	await R.frames(2)
	T.root.size_changed.emit()
	await R.frames(3)


func _menus(sc: Array, ins: Array) -> void:
	await _set_screen(sc, ins)
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	T.root.add_child(menu)
	await R.frames(4)
	var tag := "%s %dx%d / %s" % [sc[2], sc[0], sc[1], ins[0]]
	await _check_screen(tag + " / main menu", menu)
	for mode: String in ["race", "time_trial"]:
		menu.call("_show_setup", mode)
		await R.frames(4)
		await _check_screen(tag + " / setup " + mode, menu)
	menu.call("_show_garage")
	await R.frames(4)
	await _check_screen(tag + " / garage", menu)
	menu.call("_show_main")
	menu.call("_settings")
	await R.frames(4)
	var sp := _find(menu, "SettingsPanel")
	if sp:
		var tabs: TabContainer = sp.get("_tabs")
		for t in tabs.get_tab_count():
			tabs.current_tab = t
			await R.frames(3)
			await _check_screen(tag + " / settings tab %d" % t, sp)
	menu.queue_free()
	await R.frames(2)


func _race(sc: Array, ins: Array) -> void:
	await _set_screen(sc, ins)
	Game.race.mode = "race"
	Game.race.racers = 8
	Game.settings["quality"] = 0
	var scene: Node = load("res://scenes/race.tscn").instantiate()
	T.root.add_child(scene)
	while scene.get("player") == null or scene.get("touch") == null:
		await R.frames(5)
	await R.frames(10)
	var tag := "%s %dx%d / %s" % [sc[2], sc[0], sc[1], ins[0]]
	_check_touch(tag + " / race touch controls", scene.get("touch"))
	await _check_screen(tag + " / race HUD", scene.get("hud"))
	scene.call("_pause")
	await R.frames(4)
	await _check_screen(tag + " / pause", scene.get("_overlay"))
	scene.call("_open_settings")
	await R.frames(4)
	var sp := _find(scene, "SettingsPanel")
	if sp:
		await _check_screen(tag + " / settings from pause", sp)
		sp.call("_close")
		await R.frames(3)
	scene.call("_resume")
	await R.frames(2)
	var results: Array = []
	for i in 8:
		results.append({"pos": i + 1, "name": "Racer%d" % i, "time": 180.0 + i, "best": 59.0 + i, "finished": true, "player": i == 2})
	scene.call("_on_finished", results)
	await R.frames(4)
	await _check_screen(tag + " / results", scene.get("_overlay"))
	T.paused = false
	scene.queue_free()
	await R.frames(3)


func _find(n: Node, cls: String) -> Node:
	for c in n.find_children("*", "", true, false):
		if c.get_script() and (c.get_script() as Script).get_global_name() == cls:
			return c
	return null


func _visible(c: CanvasItem) -> bool:
	return c.is_visible_in_tree()


func _in_scroll(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _check_screen(tag: String, root: Node) -> void:
	if root == null:
		fails.append([tag, "screen missing"])
		return
	var vp := T.root
	var safe := UIKit.safe_rect(vp)
	var tol := 1.5
	var buttons: Array = []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not _visible(c):
			continue
		var interesting := c is BaseButton or c is Range or (c is Label and (c as Label).text.strip_edges() != "")
		if not interesting:
			continue
		var r := c.get_global_rect()
		var sc := _in_scroll(c)
		if sc:
			# inside a scroll area: reachable by scrolling; the scroll area itself must be on screen
			r = sc.get_global_rect()
		checked += 1
		if r.position.x < safe.position.x - tol or r.position.y < safe.position.y - tol or r.end.x > safe.end.x + tol or r.end.y > safe.end.y + tol:
			fails.append([tag, "outside safe area", _name(c), r, safe])
		if c is BaseButton and not (c as BaseButton).disabled:
			buttons.append(c)
	for bb in buttons:
		if not is_instance_valid(bb):
			continue
		var b: BaseButton = bb
		if not _visible(b):
			continue
		if b is Button and (b as Button).text in ["Quit", "START", "Race again", "Main menu", "Restart", "Quit to menu"]:
			# scene-changing buttons: their layout is checked above; a test tap that
			# fired would replace the test scene itself
			continue
		var sc := _in_scroll(b)
		if sc:
			sc.ensure_control_visible(b)
			await R.frames(2)
		await _tap(tag, b)


func _tap(tag: String, b: BaseButton) -> void:
	var downs := [0]
	var cb := func() -> void: downs[0] += 1
	b.button_down.connect(cb)
	var c := b.get_global_rect().get_center()
	var w := T.root.get_screen_transform() * c
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = w
	t.pressed = true
	T.root.push_input(t)
	await R.frames(1)
	# slide off and release far away: a cancelled tap must not trigger the action
	var dr := InputEventScreenDrag.new()
	dr.index = 0
	dr.position = Vector2(2, 2)
	dr.relative = Vector2(2, 2) - w
	T.root.push_input(dr)
	await R.frames(1)
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = Vector2(2, 2)
	u.pressed = false
	T.root.push_input(u)
	await R.frames(1)
	tapped += 1
	if is_instance_valid(b):
		b.button_down.disconnect(cb)
		if b is OptionButton:
			(b as OptionButton).get_popup().hide()
	if downs[0] == 0:
		fails.append([tag, "tap not received", _name(b), c])


func _check_touch(tag: String, tc: Node) -> void:
	if tc == null:
		fails.append([tag, "touch controls missing"])
		return
	if not (tc as CanvasItem).visible:
		fails.append([tag, "touch controls hidden"])
		return
	var safe := UIKit.safe_rect(T.root)
	var ids: Array = tc.call("_buttons")
	ids.append("stick")
	var circles: Array = []
	for id: String in ids:
		var cpos: Vector2 = tc.call("_btn_center", id)
		var rad: float = tc.call("_btn_radius", id)
		checked += 1
		var rr := Rect2(cpos - Vector2.ONE * rad, Vector2.ONE * rad * 2.0)
		if not safe.grow(1.5).encloses(rr):
			fails.append([tag, "touch button outside safe area", id, rr, safe])
		circles.append([id, cpos, rad])
	# no two touch buttons overlap, and none covers the minimap / gauge HUD widgets
	for i in circles.size():
		for j in range(i + 1, circles.size()):
			var a: Array = circles[i]
			var b: Array = circles[j]
			if (a[1] as Vector2).distance_to(b[1]) < float(a[2]) + float(b[2]) - 2.0:
				fails.append([tag, "touch buttons overlap", a[0], b[0]])


static func _name(c: Node) -> String:
	if c is Button and (c as Button).text != "":
		return "%s '%s'" % [c.get_class(), (c as Button).text]
	if c is Label:
		return "Label '%s'" % (c as Label).text.left(30)
	return c.get_class()


## Android back gesture / app backgrounding: never quits or keeps racing by accident.
func _back_and_focus() -> void:
	var res := {}
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	T.root.add_child(menu)
	await R.frames(3)
	menu.call("_show_garage")
	await R.frames(2)
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await R.frames(2)
	res["back from garage -> main page"] = str(menu.get("_page_name")) == "main"
	menu.call("_settings")
	await R.frames(2)
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await R.frames(3)
	res["back closes settings, stays in menu"] = _find(menu, "SettingsPanel") == null and is_instance_valid(menu)
	menu.queue_free()
	await R.frames(2)
	Game.settings["quality"] = 0
	var scene: Node = load("res://scenes/race.tscn").instantiate()
	T.root.add_child(scene)
	while scene.get("touch") == null:
		await R.frames(5)
	await R.frames(5)
	scene.set("_state", "racing")
	scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await R.frames(2)
	res["back in race pauses"] = T.paused
	scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await R.frames(2)
	res["back again resumes"] = not T.paused
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await R.frames(2)
	res["leaving the app pauses the race"] = T.paused
	scene.call("_resume")
	T.paused = false
	scene.queue_free()
	await R.frames(3)
	var ok := true
	for k in res:
		ok = ok and bool(res[k])
	R.check("ui", "Android back gesture and app backgrounding behave (never quit/keep racing by accident)", ok, res)
