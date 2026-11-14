class_name CarPreview
extends SubViewportContainer
## Turntable 3D preview of the player's car (own isolated world).

var vp: SubViewport
var pivot: Node3D
var model: Node3D
var _spin := 0.6
var _drag := false
var _team := 0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.65)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(2.6, 1.25, 2.9)
	cam.fov = 34.0
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.12, 0))
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.5, 0.7, 1.0)
	vp.add_child(rim)
	pivot = Node3D.new()
	vp.add_child(pivot)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.05
	cm.bottom_radius = 1.1
	cm.height = 0.05
	cm.radial_segments = 48
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.06, 0.07, 0.1)
	dm.metallic = 0.2
	dm.roughness = 0.6
	dm.emission_enabled = true
	dm.emission = Color(0.1, 0.5, 1.0)
	dm.emission_energy_multiplier = 0.05
	disc.material_override = dm
	disc.position.y = -0.2
	pivot.add_child(disc)
	refresh()


func set_team(t: int) -> void:
	_team = t
	refresh()


func refresh() -> void:
	if pivot == null:
		return
	if model:
		model.queue_free()
	model = CarModel.build(int(Settings.get_value("car_body", 0)), Phys.team_color(_team), Settings.accent_color())
	pivot.add_child(model)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_drag = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _drag:
		pivot.rotation.y += (event as InputEventMouseMotion).relative.x * 0.01
		_spin = 0.0


func _process(delta: float) -> void:
	if not _drag:
		_spin = move_toward(_spin, 0.6, delta * 0.5)
	if pivot:
		pivot.rotation.y += _spin * delta
