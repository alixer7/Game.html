extends Node

## Realistic-Stylized PBR Procedural Texture & Normal-Map Synthesizer.
## Generates crisp paired Albedo + Sobel Height-to-Normal Maps for rich 3D surface lighting!

var _albedo_cache: Dictionary = {}
var _normal_cache: Dictionary = {}

func get_texture(tex_name: String) -> ImageTexture:
	if _albedo_cache.has(tex_name):
		return _albedo_cache[tex_name]
	_build_pair(tex_name)
	return _albedo_cache[tex_name]

func get_normal_map(tex_name: String) -> ImageTexture:
	if _normal_cache.has(tex_name):
		return _normal_cache[tex_name]
	_build_pair(tex_name)
	return _normal_cache[tex_name]

func _build_pair(tex_name: String) -> void:
	var pair: Dictionary
	match tex_name:
		"road_tiki":
			pair = _make_pbr_road(Color(0.48, 0.37, 0.25), Color(0.38, 0.28, 0.18), Color(0.98, 0.84, 0.30), Color(0.84, 0.18, 0.10), Color(0.94, 0.90, 0.80), true)
		"road_glacier":
			pair = _make_pbr_road(Color(0.40, 0.52, 0.68), Color(0.32, 0.44, 0.60), Color(0.20, 0.86, 1.0), Color(0.10, 0.38, 0.84), Color(0.92, 0.96, 1.0), false)
		"road_volcano":
			pair = _make_pbr_road(Color(0.16, 0.14, 0.18), Color(0.11, 0.09, 0.13), Color(1.0, 0.50, 0.08), Color(0.92, 0.20, 0.06), Color(1.0, 0.78, 0.18), true)
		"ice_surface":
			pair = _make_pbr_ice()
		"wood_bridge":
			pair = _make_pbr_wood(Color(0.50, 0.31, 0.15), Color(0.34, 0.20, 0.09))
		"offroad_sand":
			pair = _make_pbr_terrain(Color(0.80, 0.64, 0.36), Color(0.66, 0.50, 0.26), 1.8)
		"offroad_snow":
			pair = _make_pbr_terrain(Color(0.84, 0.91, 0.98), Color(0.66, 0.78, 0.92), 1.5)
		"offroad_lava_rock":
			pair = _make_pbr_terrain(Color(0.18, 0.13, 0.15), Color(0.34, 0.12, 0.06), 2.4)
		"wall_tiki":
			pair = _make_pbr_brick(Color(0.48, 0.38, 0.26), Color(0.24, 0.18, 0.12), Color(0.20, 0.44, 0.18))
		"wall_glacier":
			pair = _make_pbr_brick(Color(0.38, 0.64, 0.86), Color(0.18, 0.40, 0.68), Color(0.86, 0.95, 1.0))
		"wall_volcano":
			pair = _make_pbr_brick(Color(0.19, 0.14, 0.18), Color(0.88, 0.28, 0.04), Color(0.12, 0.09, 0.13))
		"checkerboard":
			pair = _make_simple_pair(_make_checker_img())
		"crate_item":
			pair = _make_simple_pair(_make_crate_img(Color(0.76, 0.46, 0.16), Color(1.0, 0.92, 0.25), false))
		"crate_tnt":
			pair = _make_simple_pair(_make_crate_img(Color(0.86, 0.12, 0.10), Color(1.0, 0.95, 0.30), true))
		"shortcut_kicker":
			pair = _make_pbr_kicker()
		_:
			pair = _make_pbr_terrain(Color(0.55, 0.55, 0.55), Color(0.45, 0.45, 0.45), 1.0)

	var alb: Image = pair["albedo"]
	var nrm: Image = pair["normal"]
	alb.generate_mipmaps()
	nrm.generate_mipmaps()
	_albedo_cache[tex_name] = ImageTexture.create_from_image(alb)
	_normal_cache[tex_name] = ImageTexture.create_from_image(nrm)

func _hash2(x: int, y: int) -> float:
	var n := (x * 374761393 + y * 668265263) ^ (x * 1274126177)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0x7fffffff) / 2147483647.0

func _value_noise(x: float, y: float) -> float:
	var ix := int(floorf(x))
	var iy := int(floorf(y))
	var fx := x - float(ix)
	var fy := y - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash2(ix, iy)
	var b := _hash2(ix + 1, iy)
	var c := _hash2(ix, iy + 1)
	var d := _hash2(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)

func _fbm(x: float, y: float) -> float:
	return _value_noise(x, y) * 0.55 + _value_noise(x * 2.1, y * 2.1) * 0.30 + _value_noise(x * 4.3, y * 4.3) * 0.15

func _height_to_normal(h_arr: PackedFloat32Array, w: int, h: int, strength: float = 2.6) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in range(h):
		var ym := (y - 1 + h) % h
		var yp := (y + 1) % h
		for x in range(w):
			var xm := (x - 1 + w) % w
			var xp := (x + 1) % w
			var dx := (h_arr[y * w + xp] - h_arr[y * w + xm]) * strength
			var dy := (h_arr[yp * w + x] - h_arr[ym * w + x]) * strength
			var n := Vector3(-dx, -dy, 1.0).normalized()
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return img

func _make_simple_pair(alb: Image) -> Dictionary:
	var w := alb.get_width()
	var h := alb.get_height()
	var nrm := Image.create(w, h, false, Image.FORMAT_RGB8)
	nrm.fill(Color(0.5, 0.5, 1.0))
	return {"albedo": alb, "normal": nrm}

func _make_pbr_road(col_a: Color, col_b: Color, stripe: Color, curb_a: Color, curb_b: Color, cobble: bool) -> Dictionary:
	var w := 256
	var h := 256
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var h_map := PackedFloat32Array()
	h_map.resize(w * h)
	for y in range(h):
		var curb_on := ((y / 32) % 2) == 0
		var dash_on := ((y / 32) % 2) == 0
		for x in range(w):
			var u := float(x) / float(w)
			var v := float(y) / float(h)
			var elev := 0.5
			var c: Color
			if u < 0.08 or u > 0.92:
				c = curb_a if curb_on else curb_b
				elev = 0.82 if curb_on else 0.74
				if absf(u - 0.08) < 0.012 or absf(u - 0.92) < 0.012:
					c = c.darkened(0.32)
					elev = 0.25
			else:
				var grain := _fbm(u * 22.0, v * 22.0)
				var stone_seam := 0.0
				if cobble:
					var row := int(v * 16.0)
					var sx := fmod(u * 10.0 + (0.5 if row % 2 == 1 else 0.0), 1.0)
					var sy := fmod(v * 16.0, 1.0)
					if sx < 0.06 or sy < 0.07:
						stone_seam = 1.0
				# Realistic dark dual tire wear tracks along racing lanes!
				var tire_wear := exp(-pow((u - 0.30) * 9.0, 2.0)) + exp(-pow((u - 0.70) * 9.0, 2.0))
				c = col_a.lerp(col_b, clampf(grain * 0.75 + tire_wear * 0.25 + stone_seam * 0.35, 0.0, 1.0))
				elev = 0.55 + grain * 0.28 - stone_seam * 0.42 - tire_wear * 0.08
				if absf(u - 0.105) < 0.012 or absf(u - 0.895) < 0.012:
					c = stripe.lerp(c, 0.28)
				elif absf(u - 0.5) < 0.018 and dash_on:
					c = stripe
			alb.set_pixel(x, y, c)
			h_map[y * w + x] = elev
	return {"albedo": alb, "normal": _height_to_normal(h_map, w, h, 3.0)}

func _make_pbr_ice() -> Dictionary:
	var w := 256
	var h := 256
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var h_map := PackedFloat32Array()
	h_map.resize(w * h)
	for y in range(h):
		for x in range(w):
			var u := float(x) / float(w)
			var v := float(y) / float(h)
			var n := _fbm(u * 14.0, v * 14.0)
			var crack1 := absf(sin((u * 3.0 + v * 2.0 + n * 0.3) * PI))
			var crack2 := absf(sin((u * 5.0 - v * 4.0 + n * 0.25) * PI))
			var is_crack := crack1 < 0.055 or crack2 < 0.04
			var c := Color(0.32, 0.74, 0.96).lerp(Color(0.16, 0.48, 0.84), n)
			var elev := 0.65 + n * 0.15
			if u < 0.075 or u > 0.925:
				c = Color(0.88, 0.96, 1.0) if ((y / 32) % 2 == 0) else Color(0.12, 0.44, 0.88)
				elev = 0.85
			elif is_crack:
				c = c.lightened(0.42)
				elev = 0.20
			alb.set_pixel(x, y, c)
			h_map[y * w + x] = elev
	return {"albedo": alb, "normal": _height_to_normal(h_map, w, h, 2.8)}

func _make_pbr_wood(col_a: Color, col_b: Color) -> Dictionary:
	var w := 256
	var h := 256
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var h_map := PackedFloat32Array()
	h_map.resize(w * h)
	for y in range(h):
		var gap := (y % 32) < 3
		var pid := y / 32
		for x in range(w):
			var u := float(x) / float(w)
			var v := float(y) / float(h)
			if gap:
				alb.set_pixel(x, y, col_b.darkened(0.48))
				h_map[y * w + x] = 0.08
			else:
				var grain := _fbm(u * 26.0, float(pid) * 2.3 + v * 6.0)
				var c := col_a.lerp(col_b, clampf(grain * 0.85, 0.0, 1.0))
				if u < 0.06 or u > 0.94:
					c = c.darkened(0.24)
				alb.set_pixel(x, y, c)
				h_map[y * w + x] = 0.58 + grain * 0.25
	return {"albedo": alb, "normal": _height_to_normal(h_map, w, h, 3.4)}

func _make_pbr_terrain(col_a: Color, col_b: Color, bump: float) -> Dictionary:
	var w := 128
	var h := 128
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var h_map := PackedFloat32Array()
	h_map.resize(w * h)
	for y in range(h):
		for x in range(w):
			var n := _fbm(float(x) * 0.14, float(y) * 0.14)
			alb.set_pixel(x, y, col_a.lerp(col_b, n))
			h_map[y * w + x] = n
	return {"albedo": alb, "normal": _height_to_normal(h_map, w, h, bump * 2.0)}

func _make_pbr_brick(stone: Color, mortar: Color, top_accent: Color) -> Dictionary:
	var w := 128
	var h := 128
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var h_map := PackedFloat32Array()
	h_map.resize(w * h)
	for y in range(h):
		var row := y / 32
		var off := 32 if (row % 2 == 1) else 0
		for x in range(w):
			var bx := (x + off) % 64
			var by := y % 32
			var is_m := bx < 3 or by < 3
			var n := _fbm(float(x) * 0.2, float(y) * 0.2)
			var c: Color
			var elev := 0.72 + n * 0.2
			if y < 14:
				c = top_accent.lerp(stone, n * 0.45)
			elif is_m:
				c = mortar
				elev = 0.12
			else:
				c = stone.lerp(stone.darkened(0.24), _hash2((x + off) / 16, row) * 0.65 + n * 0.35)
			alb.set_pixel(x, y, c)
			h_map[y * w + x] = elev
	return {"albedo": alb, "normal": _height_to_normal(h_map, w, h, 3.6)}

func _make_pbr_kicker() -> Dictionary:
	var w := 128
	var h := 128
	var alb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var h_map := PackedFloat32Array()
	h_map.resize(w * h)
	for y in range(h):
		var v := float(y) / float(h)
		for x in range(w):
			var u := float(x) / float(w)
			var n := _fbm(u * 14.0, v * 14.0)
			var c := Color(0.52, 0.44, 0.34).lerp(Color(0.34, 0.28, 0.22), n)
			if absf(u - 0.30) < 0.06 or absf(u - 0.70) < 0.06:
				c = c.darkened(0.28)
			var dx := absf(u - 0.5) * 2.0
			var ch := fmod(v * 2.0 + dx * 0.6, 1.0)
			if v > 0.62 and ch > 0.40 and ch < 0.54 and dx < 0.75:
				c = c.lerp(Color(1.0, 0.82, 0.28), 0.52)
			alb.set_pixel(x, y, c)
			h_map[y * w + x] = 0.5 + n * 0.4
	return {"albedo": alb, "normal": _height_to_normal(h_map, w, h, 2.8)}

func _make_checker_img() -> Image:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var white := (((x / 16) + (y / 16)) % 2) == 0
			img.set_pixel(x, y, Color(0.96, 0.96, 0.96) if white else Color(0.08, 0.08, 0.10))
	return img

func _make_crate_img(wood: Color, sym: Color, is_tnt: bool) -> Image:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var border := wood.darkened(0.35)
	for y in range(h):
		for x in range(w):
			var is_f := x < 14 or x >= w - 14 or y < 14 or y >= h - 14
			var is_s := (y % 24) < 3
			img.set_pixel(x, y, border if is_f else (wood.darkened(0.22) if is_s else wood))
	if is_tnt:
		for y in range(44, 84):
			for x in range(16, 112):
				img.set_pixel(x, y, Color(0.14, 0.04, 0.04))
		_rect(img, 24, 50, 22, 6, sym); _rect(img, 32, 56, 6, 22, sym)
		_rect(img, 54, 50, 6, 28, sym); _rect(img, 70, 50, 6, 28, sym)
		_rect(img, 84, 50, 22, 6, sym); _rect(img, 92, 56, 6, 22, sym)
	else:
		_rect(img, 46, 28, 36, 10, sym); _rect(img, 72, 36, 10, 22, sym)
		_rect(img, 56, 54, 24, 10, sym); _rect(img, 56, 60, 10, 16, sym); _rect(img, 56, 84, 12, 12, sym)
	return img

func _rect(img: Image, x0: int, y0: int, rw: int, rh: int, col: Color) -> void:
	for y in range(max(0, y0), min(img.get_height(), y0 + rh)):
		for x in range(max(0, x0), min(img.get_width(), x0 + rw)):
			img.set_pixel(x, y, col)
