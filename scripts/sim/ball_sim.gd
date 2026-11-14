class_name BallSim
extends RefCounted
## Ball rigid body state. Collisions are resolved by SimWorld.

const INV_INERTIA := 1.0 / (0.4 * Phys.BALL_MASS * Phys.BALL_R * Phys.BALL_R)

var pos := Vector3(0, Phys.BALL_R, 0)
var vel := Vector3.ZERO
var ang_vel := Vector3.ZERO
var basis := Basis.IDENTITY
var prev_pos := Vector3(0, Phys.BALL_R, 0)
var prev_quat := Quaternion.IDENTITY

var frozen := false
var last_touch_car := -1
var last_touch_team := -1
var last_touch_tick := -1000
var touched := false
var hit_flash := 0.0


func copy_from(o: BallSim) -> void:
	pos = o.pos
	vel = o.vel
	ang_vel = o.ang_vel
	basis = o.basis


func save_prev() -> void:
	prev_pos = pos
	prev_quat = basis.get_rotation_quaternion()


func reset(p: Vector3) -> void:
	pos = p
	vel = Vector3.ZERO
	ang_vel = Vector3.ZERO
	prev_pos = p
	prev_quat = basis.get_rotation_quaternion()
	last_touch_car = -1
	last_touch_team = -1
	touched = false


func integrate(dt: float) -> void:
	vel.y -= Phys.GRAVITY * dt
	vel *= pow(1.0 - Phys.BALL_DRAG, dt)
	var sp := vel.length()
	if sp > Phys.BALL_MAX_SPEED:
		vel *= Phys.BALL_MAX_SPEED / sp
	var w := ang_vel.length()
	if w > Phys.BALL_MAX_ANG:
		ang_vel *= Phys.BALL_MAX_ANG / w
		w = Phys.BALL_MAX_ANG
	pos += vel * dt
	if w > 1e-5:
		basis = Basis(ang_vel / w, w * dt) * basis
		basis = basis.orthonormalized()
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - dt * 2.5)


## Surface bounce with spin coupling. n points away from the surface.
func bounce(n: Vector3) -> void:
	var vn := vel.dot(n)
	if vn >= 0.0:
		return
	var v_perp := n * vn
	var v_para := vel - v_perp
	var s := v_para + Phys.BALL_R * n.cross(ang_vel)
	var ratio := absf(vn) / maxf(s.length(), 0.0001)
	var dv_perp := -(1.0 + Phys.BALL_RESTITUTION) * v_perp
	var dv_para := -minf(1.0, Phys.BALL_Y * ratio) * Phys.BALL_MU * s
	vel += dv_perp + dv_para
	ang_vel += Phys.BALL_A * Phys.BALL_R * dv_para.cross(n)
