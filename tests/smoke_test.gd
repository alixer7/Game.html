extends Node
## اختبار دخان آلي: يحمّل كل السكربتات، يبدأ لعبة جديدة، يحاكي اللعب، يحفظ ويحمّل.

var frames := 0
var main: Node
var phase := 0
var t0 := 0

func _ready() -> void:
	var dir_list := ["res://scripts/core", "res://scripts/data", "res://scripts/world", "res://scripts/player", "res://scripts/ai", "res://scripts/building", "res://scripts/ui", "res://scripts"]
	var bad := 0
	for d in dir_list:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".gd"):
				var s = load(d + "/" + f)
				if s == null or not s.can_instantiate():
					print("SCRIPT_FAIL ", d + "/" + f)
					bad += 1
	print("SCRIPTS_CHECKED bad=", bad)
	if OS.get_cmdline_user_args().has("--only-load"):
		get_tree().quit()
		return
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--load"):
		main._continue()
		phase = 5
	else:
		Game.delete_save()
		main._new_game()
	t0 = Time.get_ticks_msec()

func _process(_dt: float) -> void:
	frames += 1
	if phase == 4:
		if frames == 2:
			main.back_to_menu()
			print("BACK_TO_MENU ok")
		if frames == 30:
			main._continue()
			phase = 5
			frames = 0
		return
	if main == null or main.world == null or not main.world.started:
		if frames > 3000:
			print("TIMEOUT starting world")
			get_tree().quit(1)
		return
	var w = main.world
	var p = w.player
	match phase:
		0:
			print("WORLD_STARTED in ", Time.get_ticks_msec() - t0, " ms; npcs=", w.ai.npcs.size(), " settlements=", w.ai.settlements.size(), " pos=", p.global_position)
			phase = 1
			frames = 0
		1:
			w.hud.touch.joy_vec = Vector2(0, -1)
			p.sprint_on = true
			if frames % 20 == 0:
				p.try_attack()
			if frames > 240:
				phase = 2
				frames = 0
				print("MOVED to ", p.global_position, " chunks=", w.terrain.chunks.size(), " animals=", w.ai.animals.size(), " active_npcs=", w.ai.active_npcs.size())
		2:
			w.hud.touch.joy_vec = Vector2.ZERO
			for k in w.hud.panels:
				w.hud.panels[k].open() if k not in ["dialog", "trade", "storage"] else null
				w.hud.panels[k].close()
			w.hud.open_crafting("")
			w.hud.panels["crafting"].close()
			p.inventory.add("stone", 20)
			p.inventory.add("stick", 20)
			p.inventory.add("fiber", 30)
			p.inventory.add("wood", 30)
			p.inventory.add("hammer", 1)
			for r in RecipeDB.recipes:
				if r["out"] == "stone_axe":
					print("CRAFT axe: ", p.can_craft(r))
					p.craft(r)
				if r["out"] == "rope":
					p.craft(r)
			p.set_build_mode(true)
			p.build_id = "campfire"
			phase = 3
			frames = 0
		3:
			if frames == 5:
				print("BUILD plan: ", p.build_plan.get("ok"), " ", p.build_plan.get("reason", ""))
				p.press("attack")
				p.build_id = "wood_foundation"
			if frames == 10:
				print("BUILD plan2: ", p.build_plan.get("ok"), " ", p.build_plan.get("reason", ""))
				p.press("attack")
			if frames == 20:
				p.set_build_mode(false)
				print("PIECES: ", w.build.pieces.size(), " queue=", p.craft_queue.size())
				# حوار مع أقرب شخصية
				var best = null
				for n in w.ai.npcs.values():
					if best == null or n["pos"].distance_to(p.global_position) < best["pos"].distance_to(p.global_position):
						best = n
				print("NEAREST NPC ", best["name"], " ", best["role"], " dist=", best["pos"].distance_to(p.global_position))
				p.global_position = best["pos"] + Vector3(3, 2, 0)
			if frames == 200:
				print("ACTIVE NPCS after teleport: ", w.ai.active_npcs.size())
				if w.ai.active_npcs.size() > 0:
					var n = w.ai.active_npcs[0]
					w.hud.open_dialog(n)
					var d: Dictionary = n.data
					print("GREET: ", w.hud.panels["dialog"].speech.text)
					print("CHAT: ", w.ai.chat(d))
					print("PEOPLE: ", w.ai.ask_people(d))
					print("PLACE: ", w.ai.ask_place(d))
					print("GIFT: ", w.ai.gift(d, "berries", 1))
					print("RECRUIT: ", w.ai.recruit(d))
					w.hud.panels["dialog"].close()
					w.hud.open_trade(n)
					w.hud.panels["trade"].close()
				var ch = w.build.settlement_chests.values()
				if ch.size() > 0:
					w.hud.open_storage(ch[0])
					w.hud.panels["storage"].close()
				for k in ["inventory", "map", "character", "pause"]:
					w.hud.panels[k].open()
					w.hud.panels[k].refresh()
					w.hud.panels[k].close()
				var cp = w.hud.panels["character"]
				for tab in ["status", "skills", "people", "log"]:
					cp.tab = tab
					cp.open()
					cp.close()
			if frames == 260:
				w.sky.set_weather("storm")
				w.time_scale = 60.0
			if frames == 600:
				w.time_scale = 1.0
				print("TIME: ", w.sky.clock_text(), " weather=", w.sky.weather_name(), " temp=", w.temperature_at(p.global_position), " hp=", p.stats.health, " hunger=", p.stats.hunger)
				var ok = w.save_game()
				print("SAVE ok=", ok)
				phase = 4
				frames = 0
		4:
			if frames == 2:
				main.back_to_menu()
			if frames == 30:
				main._continue()
				phase = 5
				frames = 0
		5:
			if frames == 1:
				print("LOAD started; world=", main.world)
			if frames > 200:
				print("RELOADED pos=", p.global_position if is_instance_valid(p) else "?", " pieces=", main.world.build.pieces.size())
				print("SMOKE_DONE frames ok")
				get_tree().quit()
