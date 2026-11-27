extends Node

## Top-Level Application Scene Router (MainMenu <-> RaceManager).

var _active_scene: Node = null

func _ready() -> void:
	get_tree().auto_accept_quit = false
	# Lock steady 60 FPS frame pacing on 120Hz Android phones (Galaxy S24 Ultra) to prevent physics/thermal stutters!
	Engine.max_fps = 60
	_show_main_menu()

func _clear_active() -> void:
	if _active_scene and is_instance_valid(_active_scene):
		_active_scene.queue_free()
		_active_scene = null

func _show_main_menu() -> void:
	_clear_active()
	var menu := MainMenu.new()
	add_child(menu)
	_active_scene = menu
	menu.start_race_requested.connect(_start_race)

func _start_race() -> void:
	_clear_active()
	var race := RaceManager.new()
	add_child(race)
	_active_scene = race
	race.return_to_menu_requested.connect(_show_main_menu)
	race.restart_race_requested.connect(_start_race)
	race.next_gp_track_requested.connect(_start_race)
