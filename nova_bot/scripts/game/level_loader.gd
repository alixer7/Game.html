class_name LevelLoader
extends RefCounted
## Reads a level JSON file and spawns every object under `root`.
## Every object class has a `world` variable and a `setup(o: Dictionary)` method.
## JSON numbers are floats, so everything is wrapped in float()/int() by the helpers below.


static func vec(a: Variant, d: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array:
		var arr: Array = a
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return d


static func num(o: Dictionary, key: String, d: float) -> float:
	return float(o.get(key, d))


static func _grow(box: Array, v: Vector3) -> void:
	var mn: Vector3 = box[0]
	var mx: Vector3 = box[1]
	box[0] = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
	box[1] = Vector3(maxf(mx.x, v.x), maxf(mx.y, v.y), maxf(mx.z, v.z))


static func load_level(world: Node, root: Node3D, path: String) -> Dictionary:
	var parsed: Variant = null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file != null:
		parsed = JSON.parse_string(file.get_as_text())
		file.close()
	if typeof(parsed) != TYPE_DICTIONARY and LevelData.LEVELS.has(path):
		# exports that leave out *.json files still carry the embedded copy
		var emb: Dictionary = LevelData.LEVELS[path]
		parsed = emb.duplicate(true)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Level missing or invalid: " + path)
		return {}
	var data: Dictionary = parsed
	var coin_pts: Array = []
	var coin_total: int = 0
	var bots: int = 0
	var box: Array = [Vector3(1.0e9, 1.0e9, 1.0e9), Vector3(-1.0e9, -1.0e9, -1.0e9)]
	_grow(box, vec(data.get("spawn")))
	var objs: Array = data.get("objects", [])
	for item in objs:
		var o: Dictionary = item
		var t: String = str(o.get("t", ""))
		for key in ["p", "a", "b"]:
			if o.has(key):
				var pv: Vector3 = vec(o[key])
				_grow(box, pv)
				if key == "p" and o.has("off"):
					_grow(box, pv + vec(o["off"]))
		if t == "coins":
			var pts: Array = o.get("pts", [])
			for cp in pts:
				_grow(box, vec(cp))
			coin_pts.append_array(pts)
			continue
		if t == "crate":
			coin_total += int(o.get("n", 5))
		elif t == "bot":
			bots += 1
		elif t == "drone":
			coin_total += 2
		elif t == "turret" or t == "spider" or t == "snowbot":
			coin_total += 3
		elif t == "hopper":
			coin_total += 2
		elif t == "shield":
			coin_total += 4
		elif t == "boss":
			coin_total += 25
		var n: Node3D = _make(t)
		if n == null:
			push_warning("Unknown level object type: " + t)
			continue
		n.set("world", world)
		n.call("setup", o)
		root.add_child(n)
	if coin_pts.size() > 0:
		var cf := Collectibles.CoinField.new()
		cf.world = world
		cf.setup(coin_pts)
		root.add_child(cf)
	var mn: Vector3 = box[0]
	var mx: Vector3 = box[1]
	data["_center"] = (mn + mx) * 0.5
	data["_extent"] = maxf(maxf(mx.x - mn.x, mx.z - mn.z) * 0.5, 20.0)
	data["_coin_total"] = coin_total + coin_pts.size()
	data["_bots_found"] = bots
	return data


static func _make(t: String) -> Node3D:
	if t == "box" or t == "cyl":
		return Platforms.Solid.new()
	if t == "move":
		return Platforms.Moving.new()
	if t == "crumble":
		return Platforms.Crumble.new()
	if t == "ghost":
		return Platforms.Ghost.new()
	if t == "spin":
		return Platforms.Sweeper.new()
	if t == "bounce":
		return Zones.BouncePad.new()
	if t == "spad":
		return Zones.SpeedPad.new()
	if t == "updraft":
		return Zones.Updraft.new()
	if t == "zerog":
		return Zones.ZeroG.new()
	if t == "conv":
		return Zones.Conveyor.new()
	if t == "hint":
		return Zones.Hint.new()
	if t == "check":
		return Zones.Checkpoint.new()
	if t == "goal":
		return Zones.GoalPortal.new()
	if t == "switch":
		return Zones.SwitchPad.new()
	if t == "bot":
		return Collectibles.RescueBot.new()
	if t == "crate":
		return Collectibles.Crate.new()
	if t == "drone":
		return Enemies.Drone.new()
	if t == "turret":
		return Enemies.Turret.new()
	if t == "spikes":
		return Hazards.Spikes.new()
	if t == "saw":
		return Hazards.Saw.new()
	if t == "laser":
		return Hazards.Laser.new()
	if t == "bumper":
		return Hazards.Bumper.new()
	if t == "boss":
		return Boss.new()
	if t == "battery":
		return Collectibles.BatteryCell.new()
	if t == "hopper":
		return Enemies.Hopper.new()
	if t == "shield":
		return Enemies.ShieldBot.new()
	if t == "spider":
		return Enemies.Spider.new()
	if t == "snowbot":
		return Enemies.SnowBot.new()
	return null
