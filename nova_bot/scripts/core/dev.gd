class_name DevTools
extends Node
## Developer harness driven by command-line user args (everything after `--`). Inactive in normal play.
##   --level=N            start level N directly (handled by Main)
##   --tp=x,y,z           teleport the player after load      --check=N   teleport to the N-th checkpoint
##   --cam=yaw,pitch,dist set the follow camera                --free=x,y,z,lx,ly,lz  fixed overview camera
##   --shot=prefix        save screenshots (prefix_0.png ...) at the times given by --at=t0,t1,...
##   --quit=sec           quit after sec seconds               --hold=action[,action]  keep actions pressed
##   --inputs=t:act:dur;t:act:dur   timed button presses       --god   player never dies (testing)
##   --battery=pct        start battery level                   --fps   print fps once per second

var world: Node = null
var args: Dictionary = {}
var _t: float = 0.0
var _shots: Array = []
var _shot_i: int = 0
var _presses: Array = []
var _free_cam: Camera3D = null
var _fps_t: float = 0.0


static func parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = a
		if not s.begins_with("--"):
			continue
		s = s.substr(2)
		var eq: int = s.find("=")
		if eq < 0:
			out[s] = "1"
		else:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out


static func floats(s: String) -> PackedFloat64Array:
	var r := PackedFloat64Array()
	for p in s.split(",", false):
		r.append(float(p))
	return r


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if args.has("at"):
		for v in floats(str(args["at"])):
			_shots.append(v)
	if args.has("inputs"):
		for item in str(args["inputs"]).split(";", false):
			var parts: PackedStringArray = item.split(":")
			if parts.size() >= 2:
				_presses.append({"t": float(parts[0]), "a": parts[1], "d": float(parts[2]) if parts.size() > 2 else 0.1, "on": false, "done": false})
	call_deferred("_setup")


func _setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if world != null and is_instance_valid(world):
		var pl: Node = world.get("player")
		if args.has("god") and pl != null:
			pl.set("god_mode", true)
		if args.has("battery") and pl != null:
			pl.call("set_battery", float(args["battery"]))
		if args.has("check"):
			world.call("dev_goto_checkpoint", int(args["check"]))
		if args.has("tp") and pl != null:
			var f: PackedFloat64Array = floats(str(args["tp"]))
			if f.size() >= 3:
				var yaw: float = deg_to_rad(f[3]) if f.size() > 3 else 0.0
				pl.call("respawn", Vector3(f[0], f[1], f[2]), -yaw)
				var rig: Node = world.get("rig")
				rig.set("yaw", -yaw)
				rig.call("snap")
		if args.has("cam"):
			var c: PackedFloat64Array = floats(str(args["cam"]))
			var rig2: Node = world.get("rig")
			if c.size() >= 1:
				rig2.set("yaw", deg_to_rad(c[0]))
			if c.size() >= 2:
				rig2.set("pitch", c[1])
			if c.size() >= 3:
				rig2.set("dist", c[2])
			rig2.call("snap")
	if args.has("free"):
		var fc: PackedFloat64Array = floats(str(args["free"]))
		_free_cam = Camera3D.new()
		_free_cam.fov = 60.0
		_free_cam.far = 1500.0
		get_tree().root.add_child(_free_cam)
		_free_cam.global_position = Vector3(fc[0], fc[1], fc[2])
		_free_cam.look_at(Vector3(fc[3], fc[4], fc[5]), Vector3.UP)
		_free_cam.current = true
	if args.has("hold"):
		for a in str(args["hold"]).split(",", false):
			Input.action_press(a)


func _process(delta: float) -> void:
	_t += delta
	if _free_cam != null:
		_free_cam.current = true
	for p in _presses:
		var d: Dictionary = p
		if bool(d["done"]):
			continue
		if not bool(d["on"]) and _t >= float(d["t"]):
			d["on"] = true
			Input.action_press(str(d["a"]))
		elif bool(d["on"]) and _t >= float(d["t"]) + float(d["d"]):
			d["done"] = true
			Input.action_release(str(d["a"]))
	if _shot_i < _shots.size() and _t >= float(_shots[_shot_i]):
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "%s_%d.png" % [str(args.get("shot", "/tmp/shot")), _shot_i]
		img.save_png(path)
		print("DEV shot saved ", path)
		_shot_i += 1
	if args.has("fps"):
		_fps_t += delta
		if _fps_t > 1.0:
			_fps_t = 0.0
			var pl: Node = world.get("player") if world != null else null
			var pos: Vector3 = (pl as Node3D).global_position if pl != null else Vector3.ZERO
			print("DEV t=%.1f fps=%d pos=%s" % [_t, Engine.get_frames_per_second(), str(pos)])
	if args.has("quit") and _t >= float(args["quit"]):
		get_tree().quit()


## Studio scene for inspecting the robot: --model[=pose,pose,...]  (idle run punch1 punch3 spin hover dash charge air fall low swap shutdown wave)
class ModelStudio extends Node3D:
	var poses: PackedStringArray = PackedStringArray(["idle", "run", "punch1", "hover"])
	var _bots: Array = []
	var _t: float = 0.0

	func _ready() -> void:
		Mats.clear()
		Mats.theme = EnvBuilder.theme("launch")
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.12, 0.14, 0.2)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.65, 0.8)
		env.ambient_light_energy = 0.6
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.glow_enabled = true
		env.glow_intensity = 0.5
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		add_child(sun)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-20.0, 200.0, 0.0)
		fill.light_energy = 0.4
		fill.light_color = Color(0.5, 0.8, 1.0)
		add_child(fill)
		var floor_mi := MeshInstance3D.new()
		floor_mi.mesh = Geo.box(Vector3(30.0, 0.2, 10.0))
		floor_mi.material_override = Mats.std(Color(0.25, 0.27, 0.32), 0.0, 0.7)
		floor_mi.position = Vector3(0.0, -0.1, 0.0)
		add_child(floor_mi)
		for i in range(poses.size()):
			var r := RobotModel.make(Color(0.25, 0.9, 1.0))
			add_child(r)
			r.position = Vector3((float(i) - float(poses.size() - 1) * 0.5) * 1.5, 0.0, 0.0)
			r.rotation.y = PI + 0.5
			_bots.append(r)
		var cam := Camera3D.new()
		cam.fov = 40.0
		add_child(cam)
		var w: float = float(poses.size()) * 1.5
		cam.position = Vector3(0.0, 1.25, 0.9 + w * 0.8)
		cam.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)
		cam.current = true

	func _process(delta: float) -> void:
		_t += delta
		for i in range(_bots.size()):
			var r: RobotModel = _bots[i]
			var p: String = poses[i]
			r.grounded = true
			r.speed_ratio = 0.0
			r.vy = 0.0
			match p:
				"run":
					r.speed_ratio = 1.0
				"walk":
					r.speed_ratio = 0.45
				"punch1":
					r.punch = 1
					r.punch_t = fposmod(_t * 1.4, 1.0) if _t < 1.2 else 0.42
				"punch2":
					r.punch = 2
					r.punch_t = 0.42
				"punch3":
					r.punch = 3
					r.punch_t = 0.42
				"spin":
					r.spinning = true
				"spinbig":
					r.spinning = true
					r.spin_big = true
				"hover":
					r.grounded = false
					r.hovering = true
					r.position.y = 0.6
				"dash":
					r.grounded = false
					r.dashing = true
					r.position.y = 0.5
				"charge":
					r.charging = 1.0
				"air":
					r.grounded = false
					r.vy = 8.0
					r.position.y = 0.6
				"fall":
					r.grounded = false
					r.vy = -15.0
					r.position.y = 0.6
				"low":
					r.low_power = 1.0
					r.battery_level = 0.05
					r.speed_ratio = 0.4
				"swap":
					r.pose_override = "swap_look"
					r.set_clamps(1.0)
				"flex":
					r.pose_override = "swap_flex"
				"shutdown":
					r.pose_override = "shutdown"
				"wave":
					r.wave = true
				"celebrate":
					r.celebrate = true
				"happy":
					r.set_mood(1, 1.0)
				"hurt":
					r.set_mood(2, 1.0)
				"back":
					r.rotation.y = 0.3
