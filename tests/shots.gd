extends Node
## يلتقط صوراً للعبة في بيئات مختلفة (للتحقق البصري).

var main: Node
var step := 0
var wait := 0
var shots := []
var out_dir := ""

func _ready() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	Game.delete_save()
	main._new_game()

func _snap(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")
	print("SHOT ", name)

func _goto(w, pos: Vector3, yaw: float, pitch: float, hour: float) -> void:
	var p = w.player
	pos.y = w.gen.height_at(pos.x, pos.z) + 0.2
	p.global_position = pos
	p.cam_yaw.rotation.y = yaw
	p.cam_pitch.rotation.x = pitch
	w.sky.hours = floor(w.sky.hours / 24.0) * 24.0 + hour
	w.terrain.generate_now(pos, 2)

func _process(_dt: float) -> void:
	if main == null or main.world == null or not main.world.started:
		return
	var w = main.world
	wait += 1
	if wait < 50:
		return
	wait = 0
	var p = w.player
	match step:
		0:
			w.sky.set_weather("clear")
			w.sky.cloud = 0.25
			_goto(w, p.global_position, 0.6, -0.15, 9.0)
		1: _snap("01_spawn_morning")
		2:
			var s = w.ai.settlements[0]
			_goto(w, s["pos"] + Vector3(16, 0, 16), deg_to_rad(45), -0.2, 16.5)
		3: _snap("02_village")
		4:
			var target = _find_biome(w, WorldGen.FOREST)
			_goto(w, target, 1.2, -0.05, 11.0)
		5: _snap("03_forest")
		6:
			_goto(w, _find_biome(w, WorldGen.DESERT), 2.0, -0.1, 13.0)
		7: _snap("04_desert")
		8:
			_goto(w, _find_biome(w, WorldGen.SNOW), 0.3, 0.05, 12.0)
		9: _snap("05_snow_mountains")
		10:
			var v: Vector2 = w.gen.volcano
			_goto(w, Vector3(v.x + 150, 0, v.y + 150), deg_to_rad(45), 0.1, 18.6)
		11: _snap("06_volcano_sunset")
		12:
			_goto(w, _find_biome(w, WorldGen.TAIGA), 0.0, -0.1, 23.0)
			p.inventory.slots[0] = {"id": "torch", "n": 1, "d": 300.0, "a": 0.0}
			p.select_slot(0)
		13: _snap("07_night_torch")
		14:
			_goto(w, _find_biome(w, WorldGen.SWAMP), 1.0, -0.1, 15.0)
			w.sky.set_weather("rain")
			w.sky.rain = 0.8
			w.sky.cloud = 0.85
		15: _snap("08_swamp_rain")
		16:
			_goto(w, _find_biome(w, WorldGen.BEACH), 3.5, -0.05, 17.5)
			w.sky.set_weather("clear")
			w.sky.rain = 0.0
			w.sky.cloud = 0.2
		17: _snap("09_beach")
		18:
			w.hud.open_panel("inventory")
		19: _snap("10_ui_inventory")
		20:
			w.hud.panels["inventory"].close()
			w.hud.open_crafting("")
		21: _snap("11_ui_crafting")
		22:
			w.hud.panels["crafting"].close()
			w.hud.open_panel("map")
		23: _snap("12_ui_map")
		24:
			w.hud.panels["map"].close()
			get_tree().quit()
	step += 1

func _find_biome(w, b: int) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var best := Vector3.ZERO
	for i in range(4000):
		var x := r.randf_range(-900, 900)
		var z := r.randf_range(-900, 900)
		if w.gen.biome_at(x, z) == b:
			var s: Vector4 = w.gen.sample(x, z)
			if s.x > 0.5:
				return Vector3(x, 0, z)
	return best
