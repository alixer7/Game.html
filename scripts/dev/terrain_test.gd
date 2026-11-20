extends Node3D
# Dev harness: builds the full world and renders viewpoints to PNG files (SHOT_DIR).
var world: World
var cam: Camera3D
var shots := []
var frame := 0
var idx := 0
var ready_ok := false


func _ready():
	world = World.new()
	add_child(world)
	cam = Camera3D.new()
	add_child(cam)
	cam.far = 6000
	cam.fov = 70
	cam.current = true
	await world.build_async()
	var wd := world.data
	var only := OS.get_environment("SHOT_ONLY")
	var all := [
		["overview", Vector3(0, 900, 2600), Vector3(0, 0, 200), 0],
		["waterfall", Vector3(345, 0, -880), Vector3(300, 0, -1090), 12],
		["city", Vector3(1040, 0, 640), Vector3(1040, 0, 200), 3],
		["city_air", Vector3(650, 140, 750), Vector3(1100, 40, 0), 0],
		["highway", Vector3(-1765, 0, 120), Vector3(-1740, 0, 300), 2],
		["mountain", Vector3(-200, 0, -1580), Vector3(-450, 0, -1680), 6],
		["desert", Vector3(-1150, 0, 1350), Vector3(-1500, 0, 1100), 3],
		["ruins", Vector3(-120, 0, 1300), Vector3(-200, 0, 1440), 6],
		["forest", Vector3(-1350, 0, -1210), Vector3(-1550, 0, -1400), 2.5],
		["bridge", Vector3(150, 0, 60), Vector3(70, 0, 0), 3],
		["forest_start", Vector3(-1270, 0, -1180), Vector3(-1350, 0, -1208), 4.0],
		["forest_start2", Vector3(-1370, 0, -1225), Vector3(-1300, 0, -1195), 4.0],
		["tunnel_w", Vector3(-420, 0, -1664), Vector3(-350, 0, -1663), 1.6],
		["tunnel_e", Vector3(-330, 0, -1661), Vector3(-400, 0, -1666), 1.6],
		["tunnel_out", Vector3(-560, 0, -1640), Vector3(-450, 0, -1660), 3.0],
	]
	for s in all:
		if only == "" or only.split(",").has(s[0]):
			shots.append(s)
	_setv(0)
	ready_ok = true


func _setv(i):
	var wd := world.data
	var p: Vector3 = shots[i][1]
	var off: float = shots[i][3]
	if off > 0.0:
		p.y = wd.ground_height(p) + off
	else:
		p.y = maxf(p.y, wd.height(p.x, p.z) + 25.0)
	cam.global_position = p
	var q: Vector3 = shots[i][2]
	q.y = wd.ground_height(q) + (2.0 if off > 0 else 5.0)
	cam.look_at(q)


func _process(_d):
	if not ready_ok:
		return
	frame += 1
	if frame % 45 == 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_environment("SHOT_DIR") + "/w_" + shots[idx][0] + ".png")
		idx += 1
		if idx >= shots.size():
			get_tree().quit()
		else:
			_setv(idx)
