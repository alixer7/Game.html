extends Node

var main: Node
var step := 0
var wait := 0
var out_dir := ""
var npc = null

func _ready() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	_snap("20_main_menu")
	Game.delete_save()
	main._new_game()

func _snap(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir + "/" + name + ".png")
	print("SHOT ", name)

func _process(_dt: float) -> void:
	if main == null or main.world == null or not main.world.started:
		return
	var w = main.world
	var p = w.player
	wait += 1
	if wait < 40:
		return
	wait = 0
	match step:
		0:
			w.sky.set_weather("clear")
			w.sky.cloud = 0.2
			var s = w.ai.settlements[0]
			w.sky.hours = 10.0
			p.global_position = s["pos"] + Vector3(5, 2, 7)
			w.terrain.generate_now(p.global_position, 2)
		1:
			for n in w.ai.active_npcs:
				if is_instance_valid(n):
					npc = n
					break
			if npc:
				p.global_position = npc.global_position + Vector3(0, 0.5, 3.2)
				npc.in_dialog = true
				npc.rotation.y = 0.0
				p.cam_yaw.rotation.y = 0.0
				p.cam_pitch.rotation.x = -0.12
				p.set_first_person(true)
		2: _snap("21_npc_closeup")
		3:
			p.set_first_person(false)
			if npc:
				w.hud.open_dialog(npc)
				w.hud.panels["dialog"]._say(w.ai.chat(npc.data))
		4: _snap("22_dialog")
		5:
			w.hud.panels["dialog"].close()
			# بناء منزل صغير
			for it in [["wood", 200], ["plank", 200], ["rope", 60], ["hammer", 1], ["stone", 100], ["clay", 40]]:
				p.inventory.add(it[0], it[1])
			var c: Vector3 = w.ai.settlements[0]["pos"] + Vector3(-40, 0, -30)
			for i in range(300):
				var x: float = c.x + randf_range(-30, 30)
				var z: float = c.z + randf_range(-30, 30)
				var h: float = w.gen.height_at(x, z)
				if h > 1.5 and absf(w.gen.height_at(x + 6, z) - h) < 0.6 and absf(w.gen.height_at(x, z + 6) - h) < 0.6:
					c = Vector3(x, h, z)
					break
			p.global_position = c + Vector3(9, 2, 9)
			w.terrain.generate_now(p.global_position, 1)
			var pl = w.build.plan("wood_foundation", c, Vector3.UP, 0.4, 0)
			if pl.get("ok", false):
				w.build.place("wood_foundation", pl)
				var b = w.build.buildings[w.build.buildings.size() - 1]
				var org: Transform3D = b["origin"]
				for off in [Vector3(3, 0, 0), Vector3(0, 0, 3), Vector3(3, 0, 3)]:
					var pp = w.build.plan("wood_foundation", org * off, Vector3.UP, 0.0, 0)
					if pp.get("ok", false):
						w.build.place("wood_foundation", pp)
				var walls := [[Vector3(-1.4, 0.3, 0), "stone_wall"], [Vector3(-1.4, 0.3, 3), "stone_window"], [Vector3(0, 0.3, -1.4), "stone_wall"], [Vector3(3, 0.3, -1.4), "stone_wall"],
					[Vector3(4.4, 0.3, 0), "stone_wall"], [Vector3(4.4, 0.3, 3), "stone_window"], [Vector3(0, 0.3, 4.4), "stone_doorway"], [Vector3(3, 0.3, 4.4), "stone_wall"]]
				for wd in walls:
					var pw = w.build.plan(wd[1], org * wd[0], Vector3.UP, 0.0, 0)
					if pw.get("ok", false):
						w.build.place(wd[1], pw)
					else:
						print("wall fail ", wd, pw.get("reason"))
				var pdr = w.build.plan("wooden_door", org * Vector3(0, 0.3, 4.4), Vector3.UP, 0.0, 0)
				if pdr.get("ok", false):
					w.build.place("wooden_door", pdr)
				for rc in [[Vector3(0, 3.0, 0), 1], [Vector3(3, 3.0, 0), 3], [Vector3(0, 3.0, 3), 1], [Vector3(3, 3.0, 3), 3]]:
					var pr = w.build.plan("wood_roof", org * rc[0], Vector3.UP, 0.0, rc[1])
					if pr.get("ok", false):
						w.build.place("wood_roof", pr)
					else:
						print("roof fail ", pr.get("reason"))
				var pf = w.build.plan("campfire", org * Vector3(-3.5, 0, 6), Vector3.UP, 0.0, 0)
				if pf.get("ok", false):
					w.build.place("campfire", pf)
				var pc = w.build.plan("wooden_chest", org * Vector3(5.5, 0, 6), Vector3.UP, 0.0, 0)
				if pc.get("ok", false):
					w.build.place("wooden_chest", pc)
				print("house pieces: ", w.build.pieces.size())
				var view: Vector3 = org * Vector3(9, 0, 11)
				view.y = w.gen.height_at(view.x, view.z) + 0.3
				p.global_position = view
				var to: Vector3 = org * Vector3(1.5, 0, 1.5) - view
				p.cam_yaw.rotation.y = atan2(-to.x, -to.z)
				p.cam_pitch.rotation.x = -0.1
				w.sky.hours = 17.6
		6: pass
		7: _snap("23_house")
		8:
			w.sky.hours = 21.5
		9: _snap("24_house_night")
		10:
			w.sky.hours = 11.0
			p.set_build_mode(true)
			p.build_id = "stone_wall"
			p.cam_pitch.rotation.x = -0.35
		11: pass
		12: _snap("25_build_mode")
		13:
			p.set_build_mode(false)
			w.hud.open_panel("character")
			w.hud.panels["character"].tab = "people"
			w.hud.panels["character"].refresh()
		14: _snap("26_relations")
		15:
			get_tree().quit()
	step += 1
