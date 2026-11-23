extends Node
## Debug: render the menus (main, race setup, garage, settings tabs) to tests/results/shots/menu_*.png.

func _ready() -> void:
	_run.call_deferred()


func _snap(name: String) -> void:
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://tests/results/shots/menu_%s.png" % name)
	print("menu shot ", name)


func _run() -> void:
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	add_child(menu)
	await _snap("main")
	menu.call("_show_setup", "race")
	await _snap("setup")
	menu.call("_show_garage")
	await _snap("garage")
	menu.call("_settings")
	await _snap("settings")
	var sp := get_tree().root.find_children("*", "SettingsPanel", true, false)
	if sp.size() > 0:
		var tabs: TabContainer = sp[0].get("_tabs")
		if tabs:
			tabs.current_tab = mini(2, tabs.get_tab_count() - 1)
			await _snap("settings_controls")
	get_tree().quit()
