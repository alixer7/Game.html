class_name Main
extends Node
## Root scene manager: owns the current screen (menu or world) and the fade / loading overlay.

var _screen: Node = null
var _overlay: Control
var _fade: ColorRect
var _loading: Control
var _dots: Label
var _busy: bool = false
var _menu_page: String = "main"
var _t: float = 0.0
var _dev_args: Dictionary = {}


func _ready() -> void:
	Game.main = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.apply_display(get_viewport())
	Game.settings_changed.connect(_on_settings)
	_build_overlay()
	_dev_args = DevTools.parse_args()
	if _dev_args.has("model"):
		var studio := DevTools.ModelStudio.new()
		if str(_dev_args["model"]) != "1":
			studio.poses = str(_dev_args["model"]).split(",", false)
		add_child(studio)
		_attach_dev(null)
		_fade.color.a = 0.0
		return
	if _dev_args.has("file"):
		Game.dev_file = str(_dev_args["file"])
		Game.dev_theme = str(_dev_args.get("theme", ""))
	if _dev_args.has("level"):
		Game.current_level = clampi(int(_dev_args["level"]), 1, Game.level_count())
		_swap(_make_world, true)
	else:
		if _dev_args.has("page"):
			_menu_page = str(_dev_args["page"])
		_swap(_make_menu, true)
		if not _dev_args.is_empty():
			_attach_dev(null)


func _process(delta: float) -> void:
	if _loading.visible:
		_t += delta
		var n: int = int(_t * 3.0) % 4
		_dots.text = "جارٍ التحميل" + ".".repeat(n)


func _on_settings() -> void:
	Game.apply_display(get_viewport())


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_overlay = Control.new()
	UIKit.fill(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.layout_direction = Control.LAYOUT_DIRECTION_LTR
	layer.add_child(_overlay)
	_fade = ColorRect.new()
	UIKit.fill(_fade)
	_fade.color = Color(0.015, 0.02, 0.06, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)
	_loading = Control.new()
	UIKit.fill(_loading)
	_loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading.visible = false
	_overlay.add_child(_loading)
	_dots = UIKit.label("جارٍ التحميل", 46, UIKit.COL_CYAN)
	UIKit.place(_dots, Vector2(0.5, 0.5), Vector2(-300, -40), Vector2(600, 80))
	_loading.add_child(_dots)
	var sub := UIKit.label("NOVA BOT", 26, UIKit.COL_DIM)
	UIKit.place(sub, Vector2(0.5, 0.5), Vector2(-300, 30), Vector2(600, 50))
	_loading.add_child(sub)


# ----------------------------------------------------------- navigation
func go_menu(page: String = "main") -> void:
	_menu_page = page
	_swap(_make_menu)


func start_level(id: int) -> void:
	Game.current_level = id
	_swap(_make_world)


func _make_menu() -> Node:
	var m := MainMenu.new()
	m.start_page = _menu_page
	return m


func _make_world() -> Node:
	var w := GameWorld.new()
	w.level_id = Game.current_level
	if not _dev_args.is_empty():
		_attach_dev(w)
	return w


func _attach_dev(w: Node) -> void:
	var d := DevTools.new()
	d.world = w
	d.args = _dev_args
	if w != null:
		w.add_child(d)
	else:
		add_child(d)


func _swap(builder: Callable, instant: bool = false) -> void:
	if _busy:
		return
	_busy = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().paused = false
	Sfx.set_muffled(false)
	if not instant:
		await _fade_to(1.0, 0.28)
	if _screen != null:
		_screen.queue_free()
		_screen = null
		await get_tree().process_frame
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_screen = builder.call()
	add_child(_screen)
	await get_tree().process_frame
	_loading.visible = false
	await _fade_to(0.0, 0.35)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _fade_to(a: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, dur)
	await tw.finished


func _exit_tree() -> void:
	# release static resource caches so the engine exits cleanly
	Mats.clear()
	Geo._cache.clear()
	Debris._shapes.clear()
	Debris._live.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _screen != null and not _busy and _screen.has_method("on_back"):
			_screen.call("on_back")
