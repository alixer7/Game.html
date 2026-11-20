class_name WorldGen
extends RefCounted
## مولّد العالم: جزيرة ضخمة 2 كم × 2 كم ببيئات متنوعة، أنهار، جبال، بركان.
## كل الدوال هنا نقية (بدون حالة متغيرة) لتعمل بأمان في خيوط المعالجة الخلفية.

const HALF := 1024.0
const CHUNK := 64.0
const RES := 32
const SEA := 0.0

enum { OCEAN, BEACH, PLAINS, FOREST, SWAMP, DESERT, TAIGA, TUNDRA, MOUNTAIN, SNOW, VOLCANIC }

const BIOME_NAMES := ["المياه", "الشاطئ", "السهول الخضراء", "الغابة", "المستنقعات", "الصحراء", "غابات الصنوبر", "التندرا المتجمدة", "الجبال الصخرية", "القمم الثلجية", "الأراضي البركانية"]

var seed_value: int
var n_cont: FastNoiseLite
var n_hill: FastNoiseLite
var n_ridge: FastNoiseLite
var n_temp: FastNoiseLite
var n_moist: FastNoiseLite
var n_river: FastNoiseLite
var n_warp: FastNoiseLite
var n_detail: FastNoiseLite
var n_dune: FastNoiseLite
var volcano := Vector2.ZERO
## مواقع ممنوع فيها نثر الموارد (المستوطنات): Vector3(x, z, radius)
var clear_zones: Array = []

func _init(s: int) -> void:
	seed_value = s
	n_cont = _noise(s, 0.0011, 4)
	n_hill = _noise(s + 1, 0.0065, 4)
	n_ridge = _noise(s + 2, 0.0032, 5)
	n_temp = _noise(s + 3, 0.0012, 3)
	n_moist = _noise(s + 4, 0.0017, 3)
	n_river = _noise(s + 5, 0.0018, 2)
	n_warp = _noise(s + 6, 0.004, 2)
	n_detail = _noise(s + 7, 0.045, 2)
	n_dune = _noise(s + 8, 0.025, 1)
	var r := RandomNumberGenerator.new()
	r.seed = s * 7 + 3
	volcano = Vector2(r.randf_range(300.0, 480.0) * (1.0 if r.randf() < 0.5 else -1.0), r.randf_range(260.0, 430.0))

func _noise(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	return n

## يعيد Vector4(الارتفاع، الحرارة 0..1، الرطوبة 0..1، نسبة الجبلية)
func sample(x: float, z: float) -> Vector4:
	var wx := x + n_warp.get_noise_2d(x, z) * 70.0
	var wz := z + n_warp.get_noise_2d(z + 517.0, x - 433.0) * 70.0
	var d := sqrt(x * x + z * z) / HALF
	var cont := n_cont.get_noise_2d(wx, wz)
	var land := 1.02 - d * 1.12 + cont * 0.5
	var shore := smoothstep(-0.04, 0.2, land)
	var temp := clampf(0.5 + z / (HALF * 2.0) + n_temp.get_noise_2d(x, z) * 0.5, 0.0, 1.0)
	var moist := clampf(0.5 + n_moist.get_noise_2d(x, z) * 0.95, 0.0, 1.0)
	var hills := n_hill.get_noise_2d(wx, wz)
	var mnt := smoothstep(0.1, 0.42, cont + 0.18 * hills) * shore
	var rg := 1.0 - absf(n_ridge.get_noise_2d(wx, wz))
	rg = rg * rg
	var h := 3.2 + hills * 7.5 * (0.6 + moist * 0.4) + mnt * (rg * 92.0 + 16.0)
	var desert := smoothstep(0.62, 0.76, temp) * smoothstep(0.52, 0.38, moist)
	if desert > 0.0:
		h += desert * absf(n_dune.get_noise_2d(x, z * 0.4)) * 6.5 * (1.0 - mnt)
	var swamp := smoothstep(0.62, 0.78, moist) * smoothstep(0.28, 0.45, temp) * (1.0 - mnt)
	if swamp > 0.0:
		h = lerpf(h, 0.5 + hills * 1.4, swamp * 0.85)
	var rv := absf(n_river.get_noise_2d(wx, wz))
	var keep := (1.0 - smoothstep(0.25, 0.55, mnt)) * shore
	var valley := (1.0 - smoothstep(0.02, 0.14, rv)) * keep
	if valley > 0.0:
		h = lerpf(h, minf(h, 2.2), valley * 0.8)
		var chan := (1.0 - smoothstep(0.0, 0.035, rv)) * keep
		h = lerpf(h, -2.4, chan)
	h = lerpf(-20.0 + cont * 6.0, h, shore)
	var vd := Vector2(x, z).distance_to(volcano)
	if vd < 330.0:
		var k := 1.0 - vd / 330.0
		h += pow(k, 1.7) * 125.0
		if vd < 48.0:
			h -= (1.0 - vd / 48.0) * 40.0
	return Vector4(h, temp, moist, mnt)

func height_at(x: float, z: float) -> float:
	return sample(x, z).x

func biome_of(s: Vector4, x: float, z: float) -> int:
	var h := s.x
	if h < -0.3:
		return OCEAN
	if Vector2(x, z).distance_to(volcano) < 250.0:
		return VOLCANIC
	var t_alt := s.y - maxf(h - 25.0, 0.0) * 0.006
	if h > 62.0 or (h > 38.0 and t_alt < 0.25):
		return SNOW
	if s.w > 0.5 and h > 26.0:
		return MOUNTAIN
	var swamp := s.z > 0.66 and s.y > 0.32 and h < 5.0
	if h < 1.5 and not swamp:
		return BEACH
	if t_alt < 0.17:
		return TUNDRA
	if t_alt < 0.34:
		return TAIGA
	if s.y > 0.66 and s.z < 0.47:
		return DESERT
	if swamp:
		return SWAMP
	if s.z > 0.47:
		return FOREST
	return PLAINS

func biome_at(x: float, z: float) -> int:
	return biome_of(sample(x, z), x, z)

## درجة الحرارة الأساسية بالمئوية (بدون تأثير الوقت والطقس)
func base_temperature(x: float, z: float) -> Vector2:
	var s := sample(x, z)
	var t := -14.0 + s.y * 50.0 - maxf(s.x - 12.0, 0.0) * 0.07
	var desert := smoothstep(0.62, 0.76, s.y) * smoothstep(0.52, 0.38, s.z)
	var vd := Vector2(x, z).distance_to(volcano)
	t += (1.0 - smoothstep(60.0, 260.0, vd)) * 10.0
	var swing := 4.0 + desert * 11.0 + (1.0 - s.z) * 2.0
	return Vector2(t, swing)

func ground_color(s: Vector4, x: float, z: float) -> Color:
	var h := s.x
	var temp := s.y
	var moist := s.z
	var mnt := s.w
	var n := n_detail.get_noise_2d(x, z) * 0.5 + 0.5
	var t_alt := temp - maxf(h - 25.0, 0.0) * 0.006
	var c := Color(0.56, 0.53, 0.27).lerp(Color(0.25, 0.4, 0.12), clampf((moist - 0.3) * 2.2, 0.0, 1.0))
	c = c.lerp(Color(0.32, 0.35, 0.23), clampf((0.42 - t_alt) * 4.0, 0.0, 1.0))
	var forest := smoothstep(0.45, 0.6, moist) * (1.0 - smoothstep(0.62, 0.75, temp) * 0.5)
	c = c.lerp(Color(0.2, 0.26, 0.11).lerp(Color(0.33, 0.25, 0.14), n), forest * 0.55)
	var swamp := smoothstep(0.62, 0.76, moist) * smoothstep(0.28, 0.42, temp) * (1.0 - mnt) * (1.0 - smoothstep(4.0, 7.0, h))
	c = c.lerp(Color(0.22, 0.24, 0.12).lerp(Color(0.2, 0.16, 0.1), n), swamp * 0.85)
	var desert := smoothstep(0.6, 0.72, temp) * smoothstep(0.52, 0.42, moist)
	c = c.lerp(Color(0.86, 0.71, 0.46).lerp(Color(0.76, 0.58, 0.37), n), desert)
	var beach := (1.0 - smoothstep(0.7, 1.7, h)) * (1.0 - swamp)
	c = c.lerp(Color(0.84, 0.77, 0.57), beach)
	if h < 0.0:
		c = c.lerp(Color(0.4, 0.38, 0.28), clampf(-h / 3.0, 0.0, 1.0))
	var rockf := smoothstep(20.0, 38.0, h) * mnt
	c = c.lerp(Color(0.45, 0.43, 0.4).lerp(Color(0.36, 0.34, 0.32), n), rockf)
	var snow := clampf((0.2 - t_alt) * 6.0, 0.0, 1.0) + smoothstep(56.0, 70.0, h)
	c = c.lerp(Color(0.82, 0.84, 0.88), clampf(snow, 0.0, 1.0))
	var vd := Vector2(x, z).distance_to(volcano)
	var volc := 1.0 - smoothstep(190.0, 270.0, vd)
	if volc > 0.0:
		c = c.lerp(Color(0.16, 0.14, 0.13).lerp(Color(0.3, 0.14, 0.08), n * n), volc)
	c.a = clampf((0.42 - t_alt) * 3.0, 0.0, 1.0)
	return c

func _in_clear_zone(x: float, z: float) -> bool:
	for cz in clear_zones:
		if Vector2(x - cz.x, z - cz.y).length() < cz.z:
			return true
	return false

## بناء بيانات قطعة أرض كاملة (تعمل في خيط خلفي)
func build_chunk(cx: int, cz: int, grass_mult: float, with_grass: bool) -> Dictionary:
	var N := RES + 1
	var step := CHUNK / RES
	var ox := cx * CHUNK
	var oz := cz * CHUNK
	var W := N + 2
	var hs := PackedFloat32Array()
	hs.resize(W * W)
	var verts := PackedVector3Array()
	verts.resize(N * N)
	var cols := PackedColorArray()
	cols.resize(N * N)
	var gd := PackedFloat32Array()
	gd.resize(N * N)
	for j in range(-1, N + 1):
		for i in range(-1, N + 1):
			var x := ox + i * step
			var z := oz + j * step
			var s := sample(x, z)
			hs[(j + 1) * W + (i + 1)] = s.x
			if i >= 0 and i < N and j >= 0 and j < N:
				var vi := j * N + i
				verts[vi] = Vector3(i * step, s.x, j * step)
				cols[vi] = ground_color(s, x, z)
				var b := biome_of(s, x, z)
				gd[vi] = ResDB.grass_density.get(b, 0.0) if s.x > 0.35 else 0.0
	var norms := PackedVector3Array()
	norms.resize(N * N)
	for j in range(N):
		for i in range(N):
			var hl := hs[(j + 1) * W + i]
			var hr := hs[(j + 1) * W + i + 2]
			var hd := hs[j * W + i + 1]
			var hu := hs[(j + 2) * W + i + 1]
			var nn := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			norms[j * N + i] = nn
			# تقليل العشب على المنحدرات
			if nn.y < 0.82:
				gd[j * N + i] *= clampf((nn.y - 0.7) / 0.12, 0.0, 1.0)
	var idx := PackedInt32Array()
	idx.resize(RES * RES * 6)
	var faces := PackedVector3Array()
	faces.resize(RES * RES * 6)
	var p := 0
	for j in range(RES):
		for i in range(RES):
			var a := j * N + i
			var b2 := a + 1
			var c := a + N
			var d := c + 1
			idx[p] = a; idx[p + 1] = b2; idx[p + 2] = c
			idx[p + 3] = b2; idx[p + 4] = d; idx[p + 5] = c
			for q in range(6):
				faces[p + q] = verts[idx[p + q]]
			p += 6
	# نثر الموارد
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d_%d_%d" % [cx, cz, seed_value])
	var scatter := []
	var CAND := 80
	for k in range(CAND):
		var lx := rng.randf() * CHUNK
		var lz := rng.randf() * CHUNK
		var roll := rng.randf()
		var roll2 := rng.randf()
		var rot := rng.randf() * TAU
		var scl := rng.randf()
		var wx := ox + lx
		var wz := oz + lz
		var s2 := sample(wx, wz)
		if s2.x < 0.25:
			continue
		var bio := biome_of(s2, wx, wz)
		if not ResDB.scatter.has(bio):
			continue
		if roll > float(ResDB.scatter[bio]["n"]) / CAND:
			continue
		var tp := ResDB.pick(bio, roll2)
		if (tp == "palm" or tp == "cactus") and s2.y < 0.5:
			tp = "dead_tree" if s2.y > 0.3 else "pine"
		var td := ResDB.get_type(tp)
		if td.is_empty():
			continue
		var slope := _grid_slope(hs, W, lx / step, lz / step, step)
		if td["block"] and slope > 0.55:
			continue
		if _in_clear_zone(wx, wz):
			continue
		var sc: float = lerpf(td["scale"][0], td["scale"][1], scl)
		var hh := _grid_height(hs, W, lx / step, lz / step)
		scatter.append([tp, Vector3(lx, hh - 0.08, lz), rot, sc, k])
	var grass := []
	if with_grass and grass_mult > 0.0:
		var gcount := int(1700 * grass_mult)
		for g in range(gcount):
			var gx := rng.randf() * CHUNK
			var gz := rng.randf() * CHUNK
			var gr := rng.randf()
			var fi := gx / step
			var fj := gz / step
			var i0 := mini(int(fi), RES - 1)
			var j0 := mini(int(fj), RES - 1)
			var dens := gd[j0 * N + i0]
			if gr > dens:
				continue
			var gh := _grid_height(hs, W, fi, fj)
			var gc: Color = cols[j0 * N + i0]
			grass.append([Vector3(gx, gh - 0.03, gz), rng.randf() * TAU, rng.randf_range(0.65, 1.35), gc])
	return {"cx": cx, "cz": cz, "verts": verts, "norms": norms, "cols": cols, "idx": idx, "faces": faces, "scatter": scatter, "grass": grass}

func _grid_height(hs: PackedFloat32Array, W: int, fi: float, fj: float) -> float:
	var i0 := clampi(int(floor(fi)), 0, RES - 1)
	var j0 := clampi(int(floor(fj)), 0, RES - 1)
	var tx := clampf(fi - i0, 0.0, 1.0)
	var tz := clampf(fj - j0, 0.0, 1.0)
	var h00 := hs[(j0 + 1) * W + i0 + 1]
	var h10 := hs[(j0 + 1) * W + i0 + 2]
	var h01 := hs[(j0 + 2) * W + i0 + 1]
	var h11 := hs[(j0 + 2) * W + i0 + 2]
	# مطابقة تقسيم المثلثات
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

func _grid_slope(hs: PackedFloat32Array, W: int, fi: float, fj: float, step: float) -> float:
	var i0 := clampi(int(fi), 0, RES - 1)
	var j0 := clampi(int(fj), 0, RES - 1)
	var h00 := hs[(j0 + 1) * W + i0 + 1]
	var h10 := hs[(j0 + 1) * W + i0 + 2]
	var h01 := hs[(j0 + 2) * W + i0 + 1]
	return (absf(h10 - h00) + absf(h01 - h00)) / step

## خريطة ملونة للعالم كاملاً (تعمل في خيط خلفي)
func build_map_image(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var cell := HALF * 2.0 / size
	for py in range(size):
		var prev_h := 0.0
		for px in range(size):
			var x := -HALF + (px + 0.5) * cell
			var z := -HALF + (py + 0.5) * cell
			var s := sample(x, z)
			var c: Color
			if s.x < 0.0:
				var deep := clampf(-s.x / 18.0, 0.0, 1.0)
				c = Color(0.32, 0.55, 0.62).lerp(Color(0.08, 0.2, 0.36), deep)
			else:
				c = ground_color(s, x, z)
				var shade := clampf(1.0 + (s.x - prev_h) * 0.06, 0.7, 1.35)
				c = Color(c.r * shade, c.g * shade, c.b * shade)
			prev_h = s.x
			img.set_pixel(px, py, c)
	return img

## تضاريس بعيدة منخفضة الدقة للجزيرة كلها
func build_far_mesh_arrays(res: int) -> Array:
	var N := res + 1
	var step := HALF * 2.0 / res
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	verts.resize(N * N)
	cols.resize(N * N)
	norms.resize(N * N)
	var hs := PackedFloat32Array()
	hs.resize(N * N)
	for j in range(N):
		for i in range(N):
			var x := -HALF + i * step
			var z := -HALF + j * step
			var s := sample(x, z)
			hs[j * N + i] = s.x
			verts[j * N + i] = Vector3(x, s.x - 0.9, z)
			cols[j * N + i] = ground_color(s, x, z)
	for j in range(N):
		for i in range(N):
			var hl := hs[j * N + maxi(i - 1, 0)]
			var hr := hs[j * N + mini(i + 1, N - 1)]
			var hd := hs[maxi(j - 1, 0) * N + i]
			var hu := hs[mini(j + 1, N - 1) * N + i]
			norms[j * N + i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
	var idx := PackedInt32Array()
	for j in range(res):
		for i in range(res):
			var a := j * N + i
			idx.append_array([a, a + 1, a + N, a + 1, a + N + 1, a + N])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr

func find_spawn() -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 99
	for attempt in range(600):
		var rad := 60.0 + attempt * 1.2
		var ang := r.randf() * TAU
		var x := cos(ang) * rad
		var z := 120.0 + sin(ang) * rad * 0.6
		var s := sample(x, z)
		var b := biome_of(s, x, z)
		if (b == PLAINS or b == FOREST) and s.x > 2.0 and s.x < 20.0 and not _in_clear_zone(x, z):
			if absf(sample(x + 3, z).x - s.x) < 1.2 and absf(sample(x, z + 3).x - s.x) < 1.2:
				return Vector3(x, s.x, z)
	return Vector3(0, sample(0, 0).x + 2.0, 0)

## إيجاد مواقع مناسبة للمستوطنات حسب البيئة
func find_site(biomes: Array, avoid: Array, min_dist: float, rng: RandomNumberGenerator, min_from_origin := 0.0, max_from_origin := 900.0) -> Vector3:
	for attempt in range(900):
		var x := rng.randf_range(-HALF * 0.85, HALF * 0.85)
		var z := rng.randf_range(-HALF * 0.85, HALF * 0.85)
		var dist0 := Vector2(x, z).length()
		if dist0 < min_from_origin or dist0 > max_from_origin:
			continue
		var s := sample(x, z)
		if s.x < 1.8 or s.x > 55.0:
			continue
		var b := biome_of(s, x, z)
		if not b in biomes:
			continue
		var flat := true
		for o in [Vector2(8, 0), Vector2(-8, 0), Vector2(0, 8), Vector2(0, -8), Vector2(6, 6), Vector2(-6, -6)]:
			if absf(sample(x + o.x, z + o.y).x - s.x) > 2.2:
				flat = false
				break
		if not flat:
			continue
		var ok := true
		for a in avoid:
			if Vector2(x - a.x, z - a.z).length() < min_dist:
				ok = false
				break
		if ok:
			return Vector3(x, s.x, z)
	return Vector3.INF
