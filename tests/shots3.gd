extends Node

var main: Node
var step := 0
var wait := 0
var out_dir := ""

func _ready() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	Game.delete_save()
	main._new_game()

func _snap(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir + "/" + name + ".png")
	print("SHOT ", name)

func _find(w, b: int) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = 91
	for i in range(5000):
		var x := r.randf_range(-900, 900)
		var z := r.randf_range(-900, 900)
		var h: float = w.gen.height_at(x, z)
		if w.gen.biome_at(x, z) == b and h > 2.0 and absf(w.gen.height_at(x + 5, z) - h) < 0.8 and absf(w.gen.height_at(x, z + 5) - h) < 0.8:
			return Vector3(x, 0, z)
	return Vector3.ZERO

func _process(_dt: float) -> void:
	if main == null or main.world == null or not main.world.started:
		return
	var w = main.world
	var p = w.player
	wait += 1
	if wait < 45:
		return
	wait = 0
	match step:
		0:
			w.sky.set_weather("clear")
			w.sky.cloud = 0.3
			w.sky.hours = 10.5
			var f := _find(w, WorldGen.FOREST)
			f.y = w.gen.height_at(f.x, f.z) + 0.3
			p.global_position = f
			p.cam_yaw.rotation.y = 0.8
			p.cam_pitch.rotation.x = 0.05
			w.terrain.generate_now(f, 2)
		2: _snap("30_forest_v2")
		3:
			p.stats.health = 100.0
			var t := _find(w, WorldGen.TAIGA)
			t.y = w.gen.height_at(t.x, t.z) + 0.3
			p.global_position = t
			w.sky.hours = 14.0
			w.terrain.generate_now(t, 2)
		5: _snap("31_taiga_v2")
		6:
			get_tree().quit()
			p.inventory.add("hammer", 1)
			p.set_build_mode(true)
			p.build_id = "wood_foundation"
			w.hud._fill_build_list()
		8: _snap("32_buildbar_v2")
		9: get_tree().quit()
	step += 1
