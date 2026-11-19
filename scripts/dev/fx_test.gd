extends Node3D
var f := 0
func _ready():
	var env := GameEnv.new(); add_child(env); env.setup(2, 1, 1.0)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 60); ground.mesh = pm
	ground.material_override = Mats.triplanar(0, 0.2, Color(1.2, 1.2, 1.2)); add_child(ground)
	var fx := CarFX.new()
	add_child(fx)
	var p := fx._particles(Color(0.82, 0.82, 0.84, 0.35), 24, 1.8, 0.8, 3.2)
	add_child(p)
	p.position = Vector3(0, 0.3, 0)
	p.emitting = true
	var car := Car.new()
	add_child(car)
	car.setup("falcon", Color.RED, null, false)
	car.freeze = true
	car.position = Vector3(3, 0.5, 0)
	car.fx.sparks(Vector3(2, 0.5, 1), Vector3.UP, 0.5)
	car.fx.landed(1.0)
	car.fx.debris(Vector3(2.5, 0.5, 1), 1.0)
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 2.5, 7); cam.look_at(Vector3(0, 1, 0))
func _process(_d):
	f += 1
	if f == 12:
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/fx.png")
		get_tree().quit()
